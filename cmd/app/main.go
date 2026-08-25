package main

import (
	"Real-time-Chat/internal/config"
	"Real-time-Chat/internal/controller"
	"Real-time-Chat/internal/database"
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/logging"
	"Real-time-Chat/internal/pkg/token"
	"Real-time-Chat/internal/service"
	"Real-time-Chat/internal/ws"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/google/uuid"

	"github.com/julienschmidt/httprouter"
)

// dangerousUploadExt перечисляет расширения, которые браузер может
// выполнить как код, если открыть загруженный файл напрямую с /uploads/
// (тот же origin, что и остальное приложение). Остальные типы (фото,
// видео, документы) по-прежнему принимаются без изменений.
var dangerousUploadExt = map[string]bool{
	".html": true,
	".htm":  true,
	".xhtml": true,
	".svg":  true,
	".js":   true,
	".mjs":  true,
}

// withCORS оборачивает весь роутер, а не отдельные маршруты: preflight-запрос
// (OPTIONS) браузер шлёт на тот же путь ещё до того, как httprouter вообще
// определит, зарегистрирован ли на него обработчик, поэтому перехватываем
// его здесь и не пускаем дальше. allowedOrigins — из config.Config
// (ALLOWED_ORIGINS); пустой набор означает "разрешён любой Origin" — без
// этого браузер блокирует запросы с Flutter web к API на другом порту.
func withCORS(allowedOrigins map[string]struct{}) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			if origin != "" {
				if len(allowedOrigins) == 0 {
					w.Header().Set("Access-Control-Allow-Origin", origin)
				} else if _, ok := allowedOrigins[origin]; ok {
					w.Header().Set("Access-Control-Allow-Origin", origin)
				}
				w.Header().Set("Vary", "Origin")
			}
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

func main() {
	cfg, err := config.Load()
	if err != nil {
		// Логгер ещё не настроен (для этого нужен cfg.Env) — используем
		// временный обработчик только для этой единственной ошибки.
		slog.New(slog.NewJSONHandler(os.Stderr, nil)).Error("failed to load config", "err", err)
		os.Exit(1)
	}
	slog.SetDefault(logging.New(cfg.Env))

	db, err := database.New(cfg.DBUser, cfg.DBPass, cfg.DBName, cfg.DBHost)
	if err != nil {
		slog.Error("failed to connect to database", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	signer := token.New(token.SignerOptions{
		Now: func() time.Time {
			return time.Now().UTC()
		},
		Issuer: cfg.JWTIssuer,
		TTL:    cfg.AccessTTL,
		Secret: []byte(cfg.JWTSecret),
	})

	ws.SetAllowedOrigins(cfg.AllowedOrigins)

	c := ws.New(db)
	defer c.Close()

	ctl := controller.New()
	authorized := authMiddleware(signer)

	// --- Auth сервисы ---
	postAuthorizeService := service.NewAuthorizeService(db)
	postLoginService := service.NewLoginService(db, signer)
	postRegisterService := service.NewRegisterService(db, signer)

	// Почта и сервис отправки кода
	emailSender := service.NewEmailSender(cfg.SMTPHost, cfg.SMTPPort, cfg.SMTPUser, cfg.SMTPPassword)
	sendCodeService := service.NewSendCodeService(db, emailSender)

	// Комнаты и сообщения
	getRoomsService := service.NewGetRoomsService(db)
	postRoomsService := service.NewPostRoomsService(db)
	getConversationsService := service.NewGetConversationsService(db, db)
	getUsersService := service.NewGetUsersService(db)

	// Задачи
	getTasksService := service.NewGetTasksService(db, db)
	createTaskService := service.NewCreateTaskService(db, c, db)
	updateTaskService := service.NewUpdateTaskService(db, c, db)
	deleteTaskService := service.NewDeleteTaskService(db, db)
	getUserStatsService := service.MakeGetUserStats(db)

	// Пользователь
	getMeService := service.NewGetMeService(db)
	updateMeService := service.NewUpdateMeService(db)
	deleteMeService := service.NewDeleteMeService(db)
	getExtendedStatsService := service.NewGetExtendedStatsService(db)

	router := httprouter.New()

	// Health check
	router.GET("/health", func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		w.Header().Set("Content-Type", "application/json")
		if err := db.Ping(); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte(`{"status":"error","error":"database unreachable"}`))
			return
		}
		w.Write([]byte(`{"status":"ok"}`))
	})

	// WebSocket
	router.GET("/ws", c.ServeWS(signer, db))

	// Auth
	router.POST("/auth", authorized(ctl.PostAuthorize(postAuthorizeService)))
	router.POST("/register/send-code", ctl.PostSendCode(sendCodeService))
	router.POST("/register", ctl.PostRegister(postRegisterService))
	router.POST("/login", ctl.PostLogin(postLoginService))

	// Пользователи
	router.GET("/users", authorized(ctl.GetUsers(getUsersService)))
	router.GET("/users/me", authorized(ctl.GetMe(getMeService)))
	router.PUT("/users/me", authorized(ctl.UpdateMe(updateMeService)))
	router.DELETE("/users/me", authorized(ctl.DeleteMe(deleteMeService)))

	// Комнаты
	router.GET("/rooms", authorized(ctl.GetRooms(getRoomsService)))
	router.POST("/rooms", authorized(ctl.PostRooms(postRoomsService)))

	// История сообщений
	router.GET("/conversations/:id", authorized(ctl.GetConversations(getConversationsService)))

	// Раздача статики
	router.ServeFiles("/uploads/*filepath", http.Dir("./uploads"))

	// Загрузка файла
	router.POST("/upload", authorized(func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		r.Body = http.MaxBytesReader(w, r.Body, 10<<20)
		if err := r.ParseMultipartForm(10 << 20); err != nil {
			http.Error(w, `{"error": "file too large or malformed form"}`, http.StatusBadRequest)
			return
		}

		file, handler, err := r.FormFile("file")
		if err != nil {
			http.Error(w, `{"error": "No file received"}`, http.StatusBadRequest)
			return
		}
		defer file.Close()

		ext := strings.ToLower(filepath.Ext(handler.Filename))
		if dangerousUploadExt[ext] {
			http.Error(w, `{"error": "file type not allowed"}`, http.StatusBadRequest)
			return
		}

		os.MkdirAll("uploads", os.ModePerm)

		filename := uuid.New().String() + ext
		savePath := filepath.Join("uploads", filename)

		dst, err := os.Create(savePath)
		if err != nil {
			http.Error(w, `{"error": "Failed to create file on server"}`, http.StatusInternalServerError)
			return
		}
		defer dst.Close()

		if _, err := io.Copy(dst, file); err != nil {
			http.Error(w, `{"error": "Failed to save file"}`, http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{
			"url": "/uploads/" + filename,
		})
	}))

	// Задачи
	router.GET("/rooms/:id/tasks", authorized(ctl.GetTasks(getTasksService)))
	router.POST("/rooms/:id/tasks", authorized(ctl.CreateTask(createTaskService)))
	router.PATCH("/tasks/:id", authorized(ctl.UpdateTask(updateTaskService)))
	router.DELETE("/tasks/:id", authorized(ctl.DeleteTask(deleteTaskService)))
	router.GET("/users/me/stats", authorized(ctl.GetUserStats(getUserStatsService)))

	// Расширенная статистика
	router.GET("/users/me/extended-stats", authorized(func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		res, err := getExtendedStatsService(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}))

	addr := ":" + cfg.Port
	srv := &http.Server{
		Addr:         addr,
		Handler:      withCORS(cfg.AllowedOrigins)(logging.WithRequestID(router)),
		WriteTimeout: 15 * time.Second,
		ReadTimeout:  15 * time.Second,
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM, syscall.SIGQUIT)

	go func() {
		slog.Info("server started", "port", cfg.Port)
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			slog.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()

	<-quit
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("graceful shutdown failed", "err", err)
		os.Exit(1)
	}
	slog.Info("server stopped")
}

type middleware func(httprouter.Handle) httprouter.Handle

func authMiddleware(signer token.Signer) middleware {
	return func(next httprouter.Handle) httprouter.Handle {
		return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
			auth := r.Header.Get("Authorization")
			values := strings.Split(auth, " ")
			if len(values) != 2 {
				http.Error(w, "отсутствует заголовок авторизации", http.StatusUnauthorized)
				return
			}
			bearer, tok := values[0], values[1]
			if bearer != "Bearer" {
				http.Error(w, "неверный тип токена", http.StatusUnauthorized)
				return
			}
			userID, err := signer.Verify(tok)
			if err != nil {
				http.Error(w, err.Error(), http.StatusUnauthorized)
				return
			}
			ctx := context.WithValue(r.Context(), entity.ContextKeyUserID, userID)
			next(w, r.WithContext(ctx), ps)
		}
	}
}
