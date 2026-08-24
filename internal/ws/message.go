package ws

import (
	"encoding/json"
	"time"
)

const (
	MessageTypePresence = "presence"
	MessageTypeStatus   = "status"
	MessageTypeAuth     = "auth"
	MessageTypeMessage  = "message"
	MessageTypeTask     = "task" // ← твоя фича

	MessageOffline = "offline"
	MessageOnline  = "online"
)

// Message представляет сообщение передаваемое через WebSocket.
type Message struct {
	ID         string          `json:"id"`
	Type       string          `json:"type"`
	Sender     string          `json:"sender"`
	Receiver   string          `json:"room"`
	Text       string          `json:"data"`                  // Сюда Flutter обычно шлет текст или статус
	TaskID     string          `json:"task_id,omitempty"`     // Должно совпадать с ключом во Flutter
	TaskStatus string          `json:"task_status,omitempty"` // Поле, которое ты пытался добавить
	Metadata   json.RawMessage `json:"metadata,omitempty"`
	Timestamp  int64           `json:"timestamp"`
}

// Теперь этот метод не будет выдавать ошибку
func NewTaskMessage(sender, receiver, taskID, taskStatus string) Message {
	return Message{
		Type:       MessageTypeTask,
		Sender:     sender,
		Receiver:   receiver,
		TaskID:     taskID,
		TaskStatus: taskStatus,
		Timestamp:  time.Now().Unix(),
	}
}

// NewMessage создаёт новое сообщение с текущим временем.
func NewMessage(msgType, sender, receiver, text string) Message {
	return Message{
		Type:      msgType,
		Sender:    sender,
		Receiver:  receiver,
		Text:      text,
		Timestamp: time.Now().Unix(),
	}
}

// NewTaskMessage создаёт сообщение об обновлении задачи.
