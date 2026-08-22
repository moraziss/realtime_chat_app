package database

import (
	entity2 "Real-time-Chat/internal/entity"
	"database/sql"
	"encoding/json"
)

func (c *Conn) CreateRoom(users ...string) (string, error) {
	tx, err := c.db.Begin()
	if err != nil {
		return "", err
	}

	var roomID string
	err = tx.QueryRow(`
		INSERT INTO rooms (id, created_at) 
		VALUES (gen_random_uuid(), NOW()) 
		RETURNING id`).Scan(&roomID)
	if err != nil {
		tx.Rollback()
		return "", err
	}

	for _, userID := range users {
		tx.Exec(`
			INSERT INTO user_rooms (user_id, room_id) 
			VALUES ($1, $2)`, userID, roomID)
	}

	return roomID, tx.Commit()
}

func (c *Conn) GetRoom(userID string) ([]string, error) {
	rows, err := c.db.Query(`
		SELECT room_id FROM user_rooms 
		WHERE user_id = $1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []string
	for rows.Next() {
		var s string
		if err := rows.Scan(&s); err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	return result, nil
}

func (c *Conn) GetRooms(userID string) ([]entity2.UserRoom, error) {
	// ИСПРАВЛЕНИЕ: Добавили поддержку "чата с самим собой" (Self-ws)
	// и обеспечили актуальность имен через JOIN users
	stmt := `
		SELECT 
			ur.user_id, 
			ur.room_id, 
			u.name,
			COALESCE((SELECT text FROM conversations c WHERE c.room_id = ur.room_id ORDER BY created_at DESC LIMIT 1), '') as last_message,
			(SELECT COUNT(*) FROM conversations c 
			 WHERE c.room_id = ur.room_id 
			 AND c.user_id != $1 
			 AND (c.metadata->>'is_read' IS NULL OR c.metadata->>'is_read' = 'false')) as unread_count
		FROM user_rooms ur
		INNER JOIN users u ON u.id = ur.user_id
		WHERE ur.room_id IN (SELECT room_id FROM user_rooms WHERE user_id = $1)
		AND (
			ur.user_id != $1 OR 
			(SELECT COUNT(DISTINCT user_id) FROM user_rooms WHERE room_id = ur.room_id) = 1
		)
		ORDER BY (SELECT created_at FROM conversations c WHERE c.room_id = ur.room_id ORDER BY created_at DESC LIMIT 1) DESC NULLS LAST`

	rows, err := c.db.Query(stmt, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []entity2.UserRoom
	for rows.Next() {
		var res entity2.UserRoom
		if err := rows.Scan(&res.UserID, &res.RoomID, &res.Name, &res.LastMessage, &res.UnreadCount); err != nil {
			return nil, err
		}
		result = append(result, res)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return result, nil
}

func (c *Conn) CreateTaskWithMessage(task *entity2.Task) (string, string, error) {
	tx, err := c.db.Begin()
	if err != nil {
		return "", "", err
	}
	defer tx.Rollback()

	priority := task.Priority
	if priority == "" {
		priority = "medium"
	}

	subtasksJSON, _ := json.Marshal(task.Subtasks)
	if string(subtasksJSON) == "null" || task.Subtasks == nil {
		subtasksJSON = []byte("[]")
	}

	var taskID string
	err = tx.QueryRow(`
       INSERT INTO tasks (room_id, created_by, assigned_to, title, description, status, priority, due_date, subtasks, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, 'todo', $6, $7, $8, NOW(), NOW())
       RETURNING id
    `, task.RoomID, task.CreatedBy, task.AssignedTo, task.Title, task.Description, priority, task.DueDate, string(subtasksJSON)).Scan(&taskID)

	if err != nil {
		return "", "", err
	}

	metaMap := map[string]interface{}{
		"task_id":     taskID,
		"title":       task.Title,
		"description": task.Description,
		"status":      "todo",
		"priority":    priority,
		"accepted_by": []string{},
		"due_date":    task.DueDate,
		"subtasks":    task.Subtasks,
	}
	metaBytes, _ := json.Marshal(metaMap)

	var msgID string
	err = tx.QueryRow(`
       INSERT INTO conversations (user_id, room_id, text, metadata, created_at, updated_at)
       VALUES ($1, $2, '[Совместная задача]', $3, NOW(), NOW())
       RETURNING id
    `, task.CreatedBy, task.RoomID, string(metaBytes)).Scan(&msgID)

	if err != nil {
		return "", "", err
	}

	if err := tx.Commit(); err != nil {
		return "", "", err
	}

	return taskID, msgID, nil
}

func (c *Conn) GetDirectRoom(user1, user2 string) (string, error) {
	var roomID string
	query := `
		SELECT room_id 
		FROM user_rooms 
		WHERE room_id IN (
			SELECT room_id FROM user_rooms WHERE user_id = $1
			INTERSECT
			SELECT room_id FROM user_rooms WHERE user_id = $2
		)
		GROUP BY room_id
		HAVING COUNT(user_id) = 2
		LIMIT 1`

	err := c.db.QueryRow(query, user1, user2).Scan(&roomID)
	if err != nil {
		if err == sql.ErrNoRows {
			return "", nil
		}
		return "", err
	}
	return roomID, nil
}
