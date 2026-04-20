package entity

type UserRoom struct {
	RoomID      string `json:"room_id"`
	UserID      string `json:"user_id"`
	Name        string `json:"name,omitempty"`
	LastMessage string `json:"last_message"`
	UnreadCount int    `json:"unread_count"`
}
