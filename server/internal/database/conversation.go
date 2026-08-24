package database

import (
	"Real-time-Chat/internal/entity"
	"database/sql"
	"encoding/json"
	"time"

	"github.com/lib/pq"
)

func (c *Conn) CreateConversationReply(userID, roomID string, text string, metadata []byte) (string, error) {
	var id string

	// Защита от пустой строки в metadata: Postgres jsonb не принимает ''
	if len(metadata) == 0 {
		metadata = []byte("{}")
	}

	err := c.db.QueryRow(`
        INSERT INTO conversations (user_id, room_id, text, metadata, created_at, updated_at)
        VALUES ($1, $2, $3, $4::jsonb, NOW(), NOW())
        RETURNING id`,
		userID, roomID, text, string(metadata),
	).Scan(&id)
	return id, err // Возвращаем реальный UUID
}

func (c *Conn) GetConversations(roomID string) ([]entity.Conversation, error) {
	// Используем COALESCE чтобы старые сообщения без metadata не падали с ошибкой
	rows, err := c.db.Query(`
       SELECT id, user_id, created_at, text, COALESCE(metadata, '{}'::jsonb)
       FROM conversations
       WHERE room_id = $1
       ORDER BY created_at ASC
       LIMIT 50`, roomID)

	if err == sql.ErrNoRows {
		return []entity.Conversation{}, nil
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []entity.Conversation
	for rows.Next() {
		var res entity.Conversation
		// Сканируем 5 полей
		if err := rows.Scan(&res.ID, &res.UserID, &res.CreatedAt, &res.Text, &res.Metadata); err != nil {
			return nil, err
		}
		result = append(result, res)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if err := c.refreshTaskMetadata(result); err != nil {
		return nil, err
	}

	return result, nil
}

// refreshTaskMetadata подтягивает актуальные title/description/status/
// priority/due_date/subtasks/accepted_by из таблицы tasks для сообщений-
// носителей задач, вместо того чтобы доверять снимку, сохранённому в
// metadata на момент создания задачи. tasks — единственный источник истины
// для этих полей; остальные ключи metadata (например is_read) не трогаются.
func (c *Conn) refreshTaskMetadata(conversations []entity.Conversation) error {
	type taskRef struct {
		TaskID string `json:"task_id"`
	}

	seen := make(map[string]bool)
	var taskIDs []string
	for _, conv := range conversations {
		var ref taskRef
		if err := json.Unmarshal(conv.Metadata, &ref); err != nil || ref.TaskID == "" {
			continue
		}
		if !seen[ref.TaskID] {
			seen[ref.TaskID] = true
			taskIDs = append(taskIDs, ref.TaskID)
		}
	}
	if len(taskIDs) == 0 {
		return nil
	}

	rows, err := c.db.Query(`
       SELECT id, title, description, status, priority, due_date, subtasks, accepted_by
       FROM tasks
       WHERE id::text = ANY($1)`, pq.Array(taskIDs))
	if err != nil {
		return err
	}
	defer rows.Close()

	fresh := make(map[string]map[string]interface{})
	for rows.Next() {
		var id, title, description, status, priority string
		var dueDate *time.Time
		var subtasksJSON, acceptedByJSON []byte
		if err := rows.Scan(&id, &title, &description, &status, &priority, &dueDate, &subtasksJSON, &acceptedByJSON); err != nil {
			return err
		}

		var subtasks interface{}
		if len(subtasksJSON) > 0 {
			_ = json.Unmarshal(subtasksJSON, &subtasks)
		}
		var acceptedBy interface{}
		if len(acceptedByJSON) > 0 {
			_ = json.Unmarshal(acceptedByJSON, &acceptedBy)
		}

		entry := map[string]interface{}{
			"task_id":     id,
			"title":       title,
			"description": description,
			"status":      status,
			"priority":    priority,
			"subtasks":    subtasks,
			"accepted_by": acceptedBy,
		}
		if dueDate != nil {
			entry["due_date"] = dueDate.Format("2006-01-02T15:04:05Z07:00")
		} else {
			entry["due_date"] = nil
		}
		fresh[id] = entry
	}
	if err := rows.Err(); err != nil {
		return err
	}

	for i := range conversations {
		var ref taskRef
		if err := json.Unmarshal(conversations[i].Metadata, &ref); err != nil || ref.TaskID == "" {
			continue
		}
		entry, ok := fresh[ref.TaskID]
		if !ok {
			continue // задача удалена — оставляем последний известный снимок как есть
		}

		var stored map[string]interface{}
		if err := json.Unmarshal(conversations[i].Metadata, &stored); err != nil {
			stored = make(map[string]interface{})
		}
		for k, v := range entry {
			stored[k] = v
		}

		merged, err := json.Marshal(stored)
		if err != nil {
			continue
		}
		conversations[i].Metadata = merged
	}

	return nil
}
