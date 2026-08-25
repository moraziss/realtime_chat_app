package controller

import (
	"Real-time-Chat/internal/apperr"
	"Real-time-Chat/internal/service"
	"encoding/json"
	"net/http"

	"github.com/julienschmidt/httprouter"
)

type M map[string]interface{}

type Controller struct{}

func New() *Controller {
	return new(Controller)
}

func (c *Controller) PostAuthorize(svc service.Authorize) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		var req service.AuthorizeRequest
		res, err := svc(r.Context(), req)
		if err != nil {
			apperr.WriteError(w, r, err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}

func (c *Controller) GetConversations(svc service.GetConversations) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		res, err := svc(r.Context(), service.GetConversationsRequest{
			RoomID: ps.ByName("id"),
		})
		if err != nil {
			apperr.WriteError(w, r, err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}

func (c *Controller) PostLogin(svc service.Login) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		var req service.LoginRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			apperr.WriteError(w, r, apperr.Validation("invalid request body"))
			return
		}
		res, err := svc(r.Context(), req)
		if err != nil {
			apperr.WriteError(w, r, err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}

func (c *Controller) PostRegister(svc service.Register) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		var req service.RegisterRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			apperr.WriteError(w, r, apperr.Validation("invalid request body"))
			return
		}
		res, err := svc(r.Context(), req)
		if err != nil {
			apperr.WriteError(w, r, err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}

func (c *Controller) PostSendCode(svc service.SendCode) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		var req service.SendCodeRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			apperr.WriteError(w, r, apperr.Validation("invalid request body"))
			return
		}

		res, err := svc(r.Context(), req)
		if err != nil {
			apperr.WriteError(w, r, err)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	}
}
