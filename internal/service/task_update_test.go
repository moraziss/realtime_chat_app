package service

import (
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/ws"
	"context"
	"testing"
)

// fakeTaskRepo implements repository.Task - just enough for
// NewUpdateTaskService's status/accept branch under test.
type fakeTaskRepo struct {
	taskRoom   string
	acceptedBy []string
	status     string
}

func (f *fakeTaskRepo) GetTasks(roomID string) ([]entity.Task, error) { return nil, nil }
func (f *fakeTaskRepo) GetTaskRoom(taskID string) (string, error)     { return f.taskRoom, nil }
func (f *fakeTaskRepo) CreateTask(task *entity.Task) error            { return nil }
func (f *fakeTaskRepo) UpdateTask(task *entity.Task) error            { return nil }
func (f *fakeTaskRepo) UpdateTaskStatus(taskID, newStatus string, acceptedBy []string) error {
	f.status = newStatus
	if len(acceptedBy) > 0 {
		f.acceptedBy = acceptedBy
	}
	return nil
}
func (f *fakeTaskRepo) DeleteTask(id string) error { return nil }
func (f *fakeTaskRepo) GetUserTaskStats(userID string) (*entity.TaskStats, error) {
	return nil, nil
}
func (f *fakeTaskRepo) CreateTaskWithMessage(task *entity.Task) (string, string, error) {
	return "", "", nil
}

// AcceptTask mirrors the real database.Conn.AcceptTask logic closely enough
// for this test: only the given userID can ever be added, and status only
// flips to in_progress once at least two distinct people have accepted.
func (f *fakeTaskRepo) AcceptTask(taskID, userID string) (*entity.TaskMetadata, error) {
	already := false
	for _, u := range f.acceptedBy {
		if u == userID {
			already = true
		}
	}
	if !already {
		f.acceptedBy = append(f.acceptedBy, userID)
	}
	if f.status == "" {
		f.status = "todo"
	}
	if len(f.acceptedBy) >= 2 && f.status == "todo" {
		f.status = "in_progress"
	}
	return &entity.TaskMetadata{TaskID: taskID, Status: f.status, AcceptedBy: f.acceptedBy}, nil
}

// noopWSRepo is a minimal ws.Repository, just for constructing a real
// *ws.Chat (NewUpdateTaskService broadcasts through one on every call).
type noopWSRepo struct{}

func (noopWSRepo) GetRoom(userID string) ([]string, error)           { return nil, nil }
func (noopWSRepo) GetRooms(userID string) ([]entity.UserRoom, error) { return nil, nil }
func (noopWSRepo) CreateConversationReply(userID, roomID, text string, metadata []byte) (string, error) {
	return "", nil
}
func (noopWSRepo) UpdateTaskStatus(taskID, newStatus string, acceptedBy []string) error { return nil }
func (noopWSRepo) MarkMessagesAsRead(roomID, userID string) error                       { return nil }
func (noopWSRepo) AcceptTask(taskID, userID string) (*entity.TaskMetadata, error) {
	return &entity.TaskMetadata{}, nil
}
func (noopWSRepo) GetTaskRoom(taskID string) (string, error) { return "", nil }

// TestUpdateTaskAcceptIgnoresClientSuppliedAcceptedBy guards against a real
// gap: the client's "accept" action PATCHes /tasks/:id with a self-computed
// accepted_by and status, and the server used to trust both outright. Nothing
// in the client ever sends the WS task_accept message type (which *did* have
// correct server-side enforcement via repo.AcceptTask) - the REST path was
// the only one actually used, and it had none. A modified client (or a raw
// curl call) could inject an arbitrary user ID into accepted_by, or jump
// straight to in_progress with only one person having "accepted".
func TestUpdateTaskAcceptIgnoresClientSuppliedAcceptedBy(t *testing.T) {
	repo := &fakeTaskRepo{taskRoom: "room-1"}
	hub := ws.New(noopWSRepo{})
	defer hub.Close()
	rooms := fakeRoomLister{rooms: map[string][]string{"user-1": {"room-1"}}}

	update := NewUpdateTaskService(repo, hub, rooms)
	ctx := context.WithValue(context.Background(), entity.ContextKeyUserID, "user-1")

	// The authenticated caller is user-1, but the request body claims a
	// different ID accepted the task and that it's already in_progress.
	_, err := update(ctx, UpdateTaskRequest{
		ID:         "task-1",
		Status:     "in_progress",
		AcceptedBy: []string{"someone-elses-id"},
	})
	if err != nil {
		t.Fatalf("UpdateTask() error = %v", err)
	}

	if len(repo.acceptedBy) != 1 || repo.acceptedBy[0] != "user-1" {
		t.Errorf("accepted_by = %v, want [user-1] (only the authenticated caller, never the client-supplied id)", repo.acceptedBy)
	}
	if repo.status != "todo" {
		t.Errorf("status = %q, want %q (only one real acceptance so far, not the client-claimed in_progress)", repo.status, "todo")
	}
}

func TestUpdateTaskPlainStatusChangeStillWorks(t *testing.T) {
	repo := &fakeTaskRepo{taskRoom: "room-1", status: "in_progress"}
	hub := ws.New(noopWSRepo{})
	defer hub.Close()
	rooms := fakeRoomLister{rooms: map[string][]string{"user-1": {"room-1"}}}

	update := NewUpdateTaskService(repo, hub, rooms)
	ctx := context.WithValue(context.Background(), entity.ContextKeyUserID, "user-1")

	// A plain status change (e.g. the "Завершить" button) has no
	// accepted_by at all - this must keep working exactly as before.
	res, err := update(ctx, UpdateTaskRequest{ID: "task-1", Status: "done"})
	if err != nil {
		t.Fatalf("UpdateTask() error = %v", err)
	}
	if res.Data.Status != "done" {
		t.Errorf("response status = %q, want %q", res.Data.Status, "done")
	}
	if repo.status != "done" {
		t.Errorf("repo status = %q, want %q", repo.status, "done")
	}
}
