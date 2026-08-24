package main

import (
	"Real-time-Chat/internal/controller"
	"Real-time-Chat/internal/database"
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/pkg/token"
	"Real-time-Chat/internal/service"
	"Real-time-Chat/internal/ws"
	"context"
	"encoding/json"
	"io"
	"log"
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

// allowedHTTPOrigins задаётся через ALLOWED_ORIGINS (тот же список через
// запятую, что и для WebSocket — см. internal/ws/chat.go). Если не задано,
// CORS разрешает любой Origin: без этого браузер блокирует запросы с
// Flutter web (localhost:<порт flutter run -d chrome>) к API на другом порту
// (localhost:8080), поскольку это разные origin.
var allowedHTTPOrigins = parseAllowedOrigins(os.Getenv("ALLOWED_ORIGINS"))

func parseAllowedOrigins(v string) map[string]struct{} {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil
	}
	set := make(map[string]struct{})
	for _, origin := range strings.Split(v, ",") {
		if origin = strings.TrimSpace(origin); origin != "" {
			set[origin] = struct{}{}
		}
	}
	return set
}

// withCORS оборачивает весь роутер, а не отдельные маршруты: preflight-запрос
// (OPTIONS) браузер шлёт на тот же путь ещё до того, как httprouter вообще
// определит, зарегистрирован ли на него обработчик, поэтому перехватываем
// его здесь и не пускаем дальше.
func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" {
			if len(allowedHTTPOrigins) == 0 {
				w.Header().Set("Access-Control-Allow-Origin", origin)
			} else if _, ok := allowedHTTPOrigins[origin]; ok {
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

func main() {
	var (
		dbUser    = os.Getenv("DB_USER")
		dbPass    = os.Getenv("DB_PASS")
		dbName    = os.Getenv("DB_NAME")
		jwtSecret = os.Getenv("JWT_SECRET")
		jwtIssuer = os.Getenv("JWT_ISSUER")
		port      = ":8080"
	)

	db, err := database.New(dbUser, dbPass, dbName)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	signer := token.New(token.SignerOptions{
		Now: func() time.Time {
			return time.Now().UTC()
		},
		Issuer: jwtIssuer,
		TTL:    24 * time.Hour,
		Secret: []byte(jwtSecret),
	})

	c := ws.New(db)
	defer c.Close()

	ctl := controller.New()
	authorized := authMiddleware(signer)

	// --- Auth сервисы ---
	postAuthorizeService := service.NewAuthorizeService(db)
	postLoginService := service.NewLoginService(db, signer)
	postRegisterService := service.NewRegisterService(db, signer)

	// Почта и сервис отправки кода
	emailSender := service.NewEmailSender()
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

	srv := &http.Server{
		Addr:         port,
		Handler:      withCORS(router),
		WriteTimeout: 15 * time.Second,
		ReadTimeout:  15 * time.Second,
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM, syscall.SIGQUIT)

	go func() {
		log.Printf("сервер запущен на порту %s\n", port)
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	<-quit
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal(err)
	}
	log.Println("сервер остановлен")
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
