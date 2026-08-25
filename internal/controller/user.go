package controller

import (
	"Real-time-Chat/internal/apperr"
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/service"
	"encoding/json"
	"net/http"

	"github.com/julienschmidt/httprouter"
)

func (c *Controller) GetUsers(svc service.GetUsers) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		res, err := svc(r.Context(), service.GetUsersRequest{})
		if err != nil {
			apperr.WriteError(w, r, err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}

func (c *Controller) GetUserStats(svc service.GetUserStats) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		userID, ok := r.Context().Value(entity.ContextKeyUserID).(string)
		if !ok || userID == "" {
			apperr.WriteError(w, r, apperr.Unauthorized("не авторизован"))
			return
		}

		res, err := svc(r.Context(), service.GetUserStatsRequest{UserID: userID})
		if err != nil {
			apperr.WriteError(w, r, err)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}

// GetMe возвращает данные текущего пользователя
func (c *Controller) GetMe(svc service.GetMe) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		res, err := svc(r.Context())
		if err != nil {
			apperr.WriteError(w, r, err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}

// UpdateMe обновляет данные текущего пользователя
func (c *Controller) UpdateMe(svc service.UpdateMe) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		var data map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
			apperr.WriteError(w, r, apperr.Validation("invalid request body"))
			return
		}

		if err := svc(r.Context(), data); err != nil {
			apperr.WriteError(w, r, err)
			return
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"success"}`))
	}
}

// DeleteMe удаляет текущего пользователя
func (c *Controller) DeleteMe(svc service.DeleteMe) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		if err := svc(r.Context()); err != nil {
			apperr.WriteError(w, r, err)
			return
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"success"}`))
	}
}

// GetExtendedStats возвращает расширенную статистику текущего пользователя
// (сообщения, дни в приложении, история выполнения задач).
func (c *Controller) GetExtendedStats(svc service.GetExtendedStats) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		res, err := svc(r.Context())
		if err != nil {
			apperr.WriteError(w, r, err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}
