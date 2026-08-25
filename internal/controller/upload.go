package controller

import (
	"Real-time-Chat/internal/apperr"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"github.com/julienschmidt/httprouter"
)

// dangerousUploadExt перечисляет расширения, которые браузер может
// выполнить как код, если открыть загруженный файл напрямую с /uploads/
// (тот же origin, что и остальное приложение). Остальные типы (фото,
// видео, документы) по-прежнему принимаются без изменений.
var dangerousUploadExt = map[string]bool{
	".html":  true,
	".htm":   true,
	".xhtml": true,
	".svg":   true,
	".js":    true,
	".mjs":   true,
}

// PostUpload не принимает сервис, в отличие от остальных методов
// контроллера — тут нет бизнес-логики, только сохранение файла на диск,
// поэтому это просто метод, а не фабрика httprouter.Handle.
func (c *Controller) PostUpload(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
	r.Body = http.MaxBytesReader(w, r.Body, 10<<20)
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		apperr.WriteError(w, r, apperr.Validation("file too large or malformed form"))
		return
	}

	file, handler, err := r.FormFile("file")
	if err != nil {
		apperr.WriteError(w, r, apperr.Validation("no file received"))
		return
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(handler.Filename))
	if dangerousUploadExt[ext] {
		apperr.WriteError(w, r, apperr.Validation("file type not allowed"))
		return
	}

	os.MkdirAll("uploads", os.ModePerm)

	filename := uuid.New().String() + ext
	savePath := filepath.Join("uploads", filename)

	dst, err := os.Create(savePath)
	if err != nil {
		apperr.WriteError(w, r, apperr.Internal(err))
		return
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		apperr.WriteError(w, r, apperr.Internal(err))
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"url": "/uploads/" + filename,
	})
}
