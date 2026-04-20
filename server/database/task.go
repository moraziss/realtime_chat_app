package database

import (
	"Real-time-Chat/entity"
	"encoding/json"
)

func (c *Conn) GetUserTaskStats(userID string) (*entity.TaskStats, error) {
	var stats entity.TaskStats
	query := `
       SELECT 
          COUNT(DISTINCT t.id),
          COUNT(DISTINCT t.id) FILTER (WHERE t.status = 'in_progress'),
          COUNT(DISTINCT t.id) FILTER (WHERE t.status = 'done')
       FROM tasks t
       LEFT JOIN conversations conv ON (conv.metadata::jsonb)->>'task_id' = t.id::text
       WHERE t.created_by = $1 
          OR t.assigned_to = $1 
          OR ((conv.metadata::jsonb)->'accepted_by' @> jsonb_build_array($1::text))`
	err := c.db.QueryRow(query, userID).Scan(&stats.Total, &stats.InProgress, &stats.Done)
	return &stats, err
}

func (d *Conn) AcceptTask(taskID, userID string) (*entity.TaskMetadata, error) {
	var metaJSON []byte
	err := d.db.QueryRow(`SELECT metadata FROM conversations WHERE (metadata::jsonb)->>'task_id' = $1`, taskID).Scan(&metaJSON)
	if err != nil {
		return nil, err
	}

	var meta entity.TaskMetadata
	if err := json.Unmarshal(metaJSON, &meta); err != nil {
		return nil, err
	}

	alreadyAccepted := false
	for _, u := range meta.AcceptedBy {
		if u == userID {
			alreadyAccepted = true
			break
		}
	}

	if !alreadyAccepted {
		meta.AcceptedBy = append(meta.AcceptedBy, userID)
	}

	if len(meta.AcceptedBy) >= 2 && meta.Status == "todo" {
		meta.Status = "in_progress"
		_, err = d.db.Exec(`UPDATE tasks SET status = 'in_progress', updated_at = NOW() WHERE id = $1`, taskID)
		if err != nil {
			return nil, err
		}
	}

	newMetaJSON, _ := json.Marshal(meta)
	_, err = d.db.Exec(`UPDATE conversations SET metadata = $1 WHERE (metadata::jsonb)->>'task_id' = $2`, newMetaJSON, taskID)

	return &meta, err
}

func (d *Conn) UpdateTask(task *entity.Task) error {
	subtasksJSON, _ := json.Marshal(task.Subtasks)
	if string(subtasksJSON) == "null" || task.Subtasks == nil {
		subtasksJSON = []byte("[]")
	}

	// 1. Обновляем основную таблицу tasks
	queryTask := `UPDATE tasks SET 
		title=COALESCE(NULLIF($1,''),title), 
		description=COALESCE(NULLIF($2,''),description), 
		status=COALESCE(NULLIF($3,''),status), 
		priority=COALESCE(NULLIF($4,''),priority), 
		due_date=$5, 
		subtasks=$6, 
		assigned_to=COALESCE($7,assigned_to), 
		updated_at=NOW() 
		WHERE id=$8`

	_, err := d.db.Exec(queryTask,
		task.Title,
		task.Description,
		task.Status,
		task.Priority,
		task.DueDate,
		string(subtasksJSON),
		task.AssignedTo,
		task.ID,
	)
	if err != nil {
		return err
	}

	// 2. КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Обновляем метаданные в conversations,
	// чтобы при перезаходе в чат данные (особенно due_date) подтягивались актуальные.
	// Используем jsonb_set для точечного обновления или сборку нового объекта.

	// Превращаем DueDate в строку или null для JSON
	var dueDateStr interface{}
	if task.DueDate != nil {
		dueDateStr = task.DueDate.Format("2006-01-02T15:04:05Z07:00")
	} else {
		dueDateStr = nil
	}

	queryMsg := `UPDATE conversations SET metadata = metadata || 
		jsonb_build_object(
			'title', $1::text, 
			'description', $2::text, 
			'status', $3::text, 
			'priority', $4::text,
			'due_date', $5::text,
			'subtasks', $6::jsonb
		) 
		WHERE (metadata::jsonb)->>'task_id' = $7`

	_, err = d.db.Exec(queryMsg,
		task.Title,
		task.Description,
		task.Status,
		task.Priority,
		dueDateStr,
		string(subtasksJSON),
		task.ID,
	)
	return err
}

func (c *Conn) CreateTask(task *entity.Task) error {
	if task.Priority == "" {
		task.Priority = "medium"
	}

	subtasksJSON, _ := json.Marshal(task.Subtasks)
	if string(subtasksJSON) == "null" || task.Subtasks == nil {
		subtasksJSON = []byte("[]")
	}

	return c.db.QueryRow(`
		INSERT INTO tasks (room_id, created_by, assigned_to, title, description, status, priority, due_date, subtasks, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
		RETURNING id, created_at, updated_at`,
		task.RoomID,
		task.CreatedBy,
		task.AssignedTo,
		task.Title,
		task.Description,
		task.Status,
		task.Priority,
		task.DueDate,
		string(subtasksJSON),
	).Scan(&task.ID, &task.CreatedAt, &task.UpdatedAt)
}

func (d *Conn) UpdateTaskStatus(taskID string, newStatus string, acceptedBy []string) error {
	_, err := d.db.Exec(`UPDATE tasks SET status = $1, updated_at = NOW() WHERE id = $2`, newStatus, taskID)
	if err != nil {
		return err
	}

	if len(acceptedBy) > 0 {
		acceptedByJSON, _ := json.Marshal(acceptedBy)
		queryMsg := `UPDATE conversations SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('status',$1::text,'accepted_by',$2::jsonb) WHERE (metadata::jsonb)->>'task_id' = $3`
		_, err = d.db.Exec(queryMsg, newStatus, string(acceptedByJSON), taskID)
	} else {
		queryMsg := `UPDATE conversations SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('status',$1::text) WHERE (metadata::jsonb)->>'task_id' = $2`
		_, err = d.db.Exec(queryMsg, newStatus, taskID)
	}
	return err
}

func (c *Conn) GetTasks(roomID string) ([]entity.Task, error) {
	rows, err := c.db.Query(`
       SELECT id, room_id, created_by, assigned_to, title, description, status, priority, due_date, subtasks, created_at, updated_at
       FROM tasks
       WHERE room_id = $1
       ORDER BY created_at DESC`, roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []entity.Task
	for rows.Next() {
		var t entity.Task
		if err := rows.Scan(
			&t.ID, &t.RoomID, &t.CreatedBy, &t.AssignedTo,
			&t.Title, &t.Description, &t.Status, &t.Priority,
			&t.DueDate, &t.Subtasks, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			return nil, err
		}
		result = append(result, t)
	}
	return result, nil
}

func (c *Conn) DeleteTask(id string) error {
	_, err := c.db.Exec(`DELETE FROM tasks WHERE id = $1`, id)
	if err != nil {
		return err
	}
	_, err = c.db.Exec(`DELETE FROM conversations WHERE (metadata::jsonb)->>'task_id' = $1`, id)
	return err
}

func (d *Conn) MarkMessagesAsRead(roomID, userID string) error {
	_, err := d.db.Exec(`
		UPDATE conversations 
		SET metadata = COALESCE(metadata, '{}'::jsonb) || '{"is_read": true}'::jsonb 
		WHERE room_id = $1 AND user_id != $2 AND (metadata->>'is_read' IS NULL OR metadata->>'is_read' = 'false')`,
		roomID, userID)
	return err
}
