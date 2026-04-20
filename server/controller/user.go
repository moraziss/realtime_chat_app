package controller

import (
	"Real-time-Chat/entity"
	"encoding/json"
	"net/http"

	"Real-time-Chat/service"

	"github.com/julienschmidt/httprouter"
)

func (c *Controller) GetUsers(svc service.GetUsers) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		res, err := svc(r.Context(), service.GetUsersRequest{})
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
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
			http.Error(w, `{"error": "не авторизован"}`, http.StatusUnauthorized)
			return
		}

		res, err := svc(r.Context(), service.GetUserStatsRequest{UserID: userID})
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
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
			http.Error(w, err.Error(), http.StatusInternalServerError)
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
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		if err := svc(r.Context(), data); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
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
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"success"}`))
	}
}
