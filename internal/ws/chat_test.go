package ws

import (
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/pkg/token"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

var errTaskNotFound = errors.New("task not found")

// fakeRepo is a minimal ws.Repository - just enough for the join/broadcast
// path this test exercises, without needing a real Postgres connection.
type fakeRepo struct {
	roomsByUser       map[string][]entity.UserRoom
	taskRooms         map[string]string
	updateTaskStatusN atomic.Int32
}

func (f *fakeRepo) GetRoom(userID string) ([]string, error) { return nil, nil }
func (f *fakeRepo) GetRooms(userID string) ([]entity.UserRoom, error) {
	return f.roomsByUser[userID], nil
}
func (f *fakeRepo) CreateConversationReply(userID, roomID, text string, metadata []byte) (string, error) {
	return "msg-1", nil
}
func (f *fakeRepo) UpdateTaskStatus(taskID string, newStatus string, acceptedBy []string) error {
	f.updateTaskStatusN.Add(1)
	return nil
}
func (f *fakeRepo) MarkMessagesAsRead(roomID, userID string) error { return nil }
func (f *fakeRepo) AcceptTask(taskID, userID string) (*entity.TaskMetadata, error) {
	return &entity.TaskMetadata{}, nil
}
func (f *fakeRepo) GetTaskRoom(taskID string) (string, error) {
	if room, ok := f.taskRooms[taskID]; ok {
		return room, nil
	}
	return "", errTaskNotFound
}

// fakeUsers is a minimal repository.User - ServeWS only calls GetUser.
type fakeUsers struct{}

func (fakeUsers) CreateUser(*entity.User) error                        { return nil }
func (fakeUsers) UpdateUser(*entity.User) error                        { return nil }
func (fakeUsers) DeleteUser(string) error                              { return nil }
func (fakeUsers) GetUser(id string) (*entity.User, error)              { return &entity.User{ID: id}, nil }
func (fakeUsers) GetUserByEmail(string) (entity.User, error)           { return entity.User{}, nil }
func (fakeUsers) GetUsers(string) ([]entity.User, error)               { return nil, nil }
func (fakeUsers) SaveVerificationCode(string, string, time.Time) error { return nil }
func (fakeUsers) CheckVerificationCode(string, string) (bool, error)   { return false, nil }
func (fakeUsers) DeleteVerificationCode(string) error                  { return nil }

func TestServeWSJoinBroadcastsPresenceToSelf(t *testing.T) {
	repo := &fakeRepo{roomsByUser: map[string][]entity.UserRoom{
		"user-1": {{RoomID: "room-1", UserID: "user-1"}},
	}}
	hub := New(repo)
	defer hub.Close()

	signer := token.New(token.SignerOptions{
		Now: time.Now, TTL: time.Hour, Issuer: "test-issuer", Secret: []byte("test-secret"),
	})
	tok, err := signer.Sign("user-1")
	if err != nil {
		t.Fatalf("Sign() error = %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hub.ServeWS(signer, fakeUsers{})(w, r, nil)
	}))
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws?token=" + tok
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Dial() error = %v", err)
	}
	defer conn.Close()

	// Подключение вызывает Bind -> Join, который для user-1 (согласно
	// фейковому репозиторию) состоит в room-1 - хаб рассылает presence
	// "online" в эту комнату, и подключившийся клиент сам является её
	// участником, так что должен получить это сообщение обратно.
	conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	var presence Message
	if err := conn.ReadJSON(&presence); err != nil {
		t.Fatalf("ReadJSON() error = %v", err)
	}
	if presence.Type != MessageTypePresence {
		t.Errorf("Type = %q, want %q", presence.Type, MessageTypePresence)
	}
	if presence.Sender != "user-1" {
		t.Errorf("Sender = %q, want %q", presence.Sender, "user-1")
	}
	if presence.Text != MessageOnline {
		t.Errorf("Text = %q, want %q", presence.Text, MessageOnline)
	}

	// Дальше гоняем свой статус-запрос через тот же пайплайн: отправитель
	// уже состоит в room-1, поэтому проверка доступа проходит без
	// обращения к GetRoom, а getStatus() должен увидеть активную сессию.
	if err := conn.WriteJSON(Message{Type: MessageTypeStatus, Receiver: "room-1", Text: "user-1"}); err != nil {
		t.Fatalf("WriteJSON() error = %v", err)
	}

	conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	var status Message
	if err := conn.ReadJSON(&status); err != nil {
		t.Fatalf("ReadJSON() error = %v", err)
	}
	if status.Type != MessageTypeStatus {
		t.Errorf("Type = %q, want %q", status.Type, MessageTypeStatus)
	}
	if status.Text != "1" {
		t.Errorf("Text = %q, want %q (user-1 has an active session)", status.Text, "1")
	}
}

// TestTaskUpdateDeniedForTaskOutsideClaimedRoom guards against a regression of
// a real access-control gap: the handler used to trust msg.Receiver (whatever
// room the client claimed) instead of checking which room the task actually
// belongs to. A user who belongs to *some* room could update the status of
// *any* task in the system by just knowing its ID and naming one of their own
// rooms as the claimed room.
func TestTaskUpdateDeniedForTaskOutsideClaimedRoom(t *testing.T) {
	repo := &fakeRepo{
		roomsByUser: map[string][]entity.UserRoom{
			"user-1": {{RoomID: "room-1", UserID: "user-1"}},
		},
		// task-x belongs to room-2, which user-1 is NOT a member of.
		taskRooms: map[string]string{"task-x": "room-2"},
	}
	hub := New(repo)
	defer hub.Close()

	signer := token.New(token.SignerOptions{
		Now: time.Now, TTL: time.Hour, Issuer: "test-issuer", Secret: []byte("test-secret"),
	})
	tok, err := signer.Sign("user-1")
	if err != nil {
		t.Fatalf("Sign() error = %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hub.ServeWS(signer, fakeUsers{})(w, r, nil)
	}))
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws?token=" + tok
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Dial() error = %v", err)
	}
	defer conn.Close()

	// Drain the initial presence broadcast for room-1 before the real assertion.
	conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	var presence Message
	if err := conn.ReadJSON(&presence); err != nil {
		t.Fatalf("ReadJSON() (presence) error = %v", err)
	}

	// Attacker claims room-1 (which they DO belong to) but targets task-x,
	// which actually lives in room-2.
	if err := conn.WriteJSON(Message{
		Type:     MessageTypeTask,
		Receiver: "room-1",
		TaskID:   "task-x",
		Text:     "done",
	}); err != nil {
		t.Fatalf("WriteJSON() error = %v", err)
	}

	// Follow up with a message that DOES succeed, to get a deterministic
	// signal that the event loop processed (and dropped) the task message
	// without needing an arbitrary sleep.
	if err := conn.WriteJSON(Message{Type: MessageTypeStatus, Receiver: "room-1", Text: "user-1"}); err != nil {
		t.Fatalf("WriteJSON() error = %v", err)
	}
	conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	var status Message
	if err := conn.ReadJSON(&status); err != nil {
		t.Fatalf("ReadJSON() (status) error = %v", err)
	}
	if status.Type != MessageTypeStatus {
		t.Fatalf("expected the status message to come through unblocked, got Type = %q", status.Type)
	}

	if n := repo.updateTaskStatusN.Load(); n != 0 {
		t.Errorf("UpdateTaskStatus was called %d time(s), want 0 (task belongs to a room the sender is not in)", n)
	}
}
