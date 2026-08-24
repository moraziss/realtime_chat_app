package controller

import (
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/service"
	"encoding/json"
	"net/http"

	"github.com/julienschmidt/httprouter"
)

func (c *Controller) GetRooms(svc service.GetRooms) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		res, err := svc(r.Context(), service.GetRoomsRequest{})
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}

func (c *Controller) PostRooms(svc service.PostRooms) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		ctx := r.Context()
		userID, _ := ctx.Value(entity.ContextKeyUserID).(string)

		var req service.PostRoomsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		req.UserID = userID

		res, err := svc(ctx, req)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}
