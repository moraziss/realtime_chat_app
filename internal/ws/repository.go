package ws

import "Real-time-Chat/internal/entity"

// Repository is the narrow slice of the database the WS hub actually needs.
// Chat previously depended on the concrete *database.Conn directly, which
// made the hub impossible to unit-test without a real Postgres connection;
// *database.Conn still satisfies this interface unchanged, so callers don't
// need to change, but tests can now supply a fake.
type Repository interface {
	GetRoom(userID string) ([]string, error)
	GetRooms(userID string) ([]entity.UserRoom, error)
	CreateConversationReply(userID, roomID, text string, metadata []byte) (string, error)
	UpdateTaskStatus(taskID string, newStatus string, acceptedBy []string) error
	MarkMessagesAsRead(roomID, userID string) error
	AcceptTask(taskID, userID string) (*entity.TaskMetadata, error)
}
