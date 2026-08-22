package database

import (
	"Real-time-Chat/internal/entity"
	"database/sql"
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
	return result, nil
}
