package main

import (
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

	"Real-time-Chat/chat"
	"Real-time-Chat/controller"
	"Real-time-Chat/database"
	"Real-time-Chat/entity"
	"Real-time-Chat/pkg/token"
	"Real-time-Chat/service"

	"github.com/julienschmidt/httprouter"
)

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

	c := chat.New(db)
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
	getConversationsService := service.NewGetConversationsService(db)
	getUsersService := service.NewGetUsersService(db)

	// Задачи
	getTasksService := service.NewGetTasksService(db)
	createTaskService := service.NewCreateTaskService(db, c)
	updateTaskService := service.NewUpdateTaskService(db, c)
	deleteTaskService := service.NewDeleteTaskService(db)
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
		r.ParseMultipartForm(10 << 20)

		file, handler, err := r.FormFile("file")
		if err != nil {
			http.Error(w, `{"error": "No file received"}`, http.StatusBadRequest)
			return
		}
		defer file.Close()

		os.MkdirAll("uploads", os.ModePerm)

		filename := uuid.New().String() + filepath.Ext(handler.Filename)
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
		Handler:      router,
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
