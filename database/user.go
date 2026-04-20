package database

import (
	"database/sql"
	"time"

	"Real-time-Chat/entity"
)

func (c *Conn) GetUser(id string) (*entity.User, error) {
	var user entity.User
	err := c.db.QueryRow(`
		SELECT id, name, email, avatar_url, bio, settings, created_at, updated_at
		FROM users 
		WHERE id = $1`, id).Scan(
		&user.ID,
		&user.Name,
		&user.Email,
		&user.AvatarURL,
		&user.Bio,
		&user.Settings,
		&user.CreatedAt,
		&user.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (c *Conn) GetUserByName(name string) (entity.User, error) {
	var user entity.User
	err := c.db.QueryRow(`
		SELECT id, name, email
		FROM users 
		WHERE name = $1`, name).Scan(
		&user.ID,
		&user.Name,
		&user.Email,
	)
	return user, err
}

func (c *Conn) GetUserByEmail(email string) (entity.User, error) {
	var user entity.User
	err := c.db.QueryRow(`
		SELECT id, name, email, avatar_url, bio, settings, created_at, updated_at, hashed_password
		FROM users
		WHERE email = $1`, email).Scan(
		&user.ID,
		&user.Name,
		&user.Email,
		&user.AvatarURL,
		&user.Bio,
		&user.Settings,
		&user.CreatedAt,
		&user.UpdatedAt,
		&user.HashedPassword,
	)
	if err == sql.ErrNoRows {
		err = entity.ErrUserNotFound
	}
	return user, err
}

func (c *Conn) CreateUser(user *entity.User) error {
	return c.db.QueryRow(`
		INSERT INTO users (name, email, hashed_password, settings, created_at, updated_at)
		VALUES ($1, $2, $3, $4, NOW(), NOW())
		RETURNING id`,
		user.Name, user.Email, user.HashedPassword, user.Settings,
	).Scan(&user.ID)
}

func (c *Conn) UpdateUser(user *entity.User) error {
	_, err := c.db.Exec(`
		UPDATE users 
		SET name = $1, avatar_url = $2, bio = $3, settings = $4, updated_at = NOW() 
		WHERE id = $5`,
		user.Name, user.AvatarURL, user.Bio, user.Settings, user.ID,
	)
	return err
}

func (c *Conn) DeleteUser(id string) error {
	_, err := c.db.Exec(`DELETE FROM users WHERE id = $1`, id)
	return err
}

func (c *Conn) GetUsers(currentUserID string) ([]entity.User, error) {
	rows, err := c.db.Query(`
		SELECT id, name, email, avatar_url, bio
		FROM users
		WHERE id <> $1
		ORDER BY name ASC`, currentUserID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []entity.User
	for rows.Next() {
		var user entity.User
		if err := rows.Scan(&user.ID, &user.Name, &user.Email, &user.AvatarURL, &user.Bio); err != nil {
			return nil, err
		}
		result = append(result, user)
	}
	return result, rows.Err()
}

func (c *Conn) SaveVerificationCode(email, code string, expiresAt time.Time) error {
	query := `
		INSERT INTO verification_codes (email, code, expires_at) 
		VALUES ($1, $2, $3)
		ON CONFLICT (email) 
		DO UPDATE SET code = EXCLUDED.code, expires_at = EXCLUDED.expires_at, created_at = NOW()
	`
	_, err := c.db.Exec(query, email, code, expiresAt)
	return err
}

func (c *Conn) CheckVerificationCode(email, code string) (bool, error) {
	var isValid bool
	query := `
		SELECT EXISTS (
			SELECT 1 FROM verification_codes 
			WHERE email = $1 AND code = $2 AND expires_at > NOW()
		)
	`
	err := c.db.QueryRow(query, email, code).Scan(&isValid)
	return isValid, err
}

func (c *Conn) DeleteVerificationCode(email string) error {
	_, err := c.db.Exec(`DELETE FROM verification_codes WHERE email = $1`, email)
	return err
}

func (c *Conn) GetExtendedStats(userID string) (map[string]interface{}, error) {
	stats := make(map[string]interface{})

	// 1. Количество отправленных сообщений
	var msgCount int
	err := c.db.QueryRow("SELECT COUNT(*) FROM conversations WHERE user_id = $1", userID).Scan(&msgCount)
	if err != nil {
		return nil, err
	}
	stats["messages_sent"] = msgCount

	// 2. Дата регистрации (дни в приложении)
	var createdAt time.Time
	err = c.db.QueryRow("SELECT created_at FROM users WHERE id = $1", userID).Scan(&createdAt)
	if err != nil {
		return nil, err
	}
	stats["days_since_joined"] = int(time.Since(createdAt).Hours() / 24)

	// 3. Средний приоритет выполненных задач
	var avgPriority string
	err = c.db.QueryRow(`
		SELECT t.priority 
		FROM tasks t
		LEFT JOIN conversations conv ON (conv.metadata::jsonb)->>'task_id' = t.id::text
		WHERE t.status = 'done' AND (
			t.assigned_to = $1 
			OR t.created_by = $1 
			OR ((conv.metadata::jsonb)->'accepted_by' @> jsonb_build_array($1::text))
		)
		GROUP BY t.priority 
		ORDER BY COUNT(*) DESC 
		LIMIT 1`, userID).Scan(&avgPriority)
	if err == sql.ErrNoRows {
		avgPriority = "Нет данных"
	}
	stats["favorite_priority"] = avgPriority

	// 4. История выполненных задач за последние 7 дней (с учетом принятых задач)
	rows, err := c.db.Query(`
		SELECT 
			d.day::date,
			COUNT(DISTINCT t.id) FILTER (WHERE t.status = 'done')
		FROM (
			SELECT generate_series(CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE, '1 day')::date AS day
		) d
		LEFT JOIN tasks t ON d.day = t.updated_at::date
		LEFT JOIN conversations conv ON (conv.metadata::jsonb)->>'task_id' = t.id::text
		WHERE (t.id IS NULL) OR (
			t.created_by = $1 
			OR t.assigned_to = $1 
			OR ((conv.metadata::jsonb)->'accepted_by' @> jsonb_build_array($1::text))
		)
		GROUP BY d.day
		ORDER BY d.day ASC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var history []int
	for rows.Next() {
		var day time.Time
		var count int
		if err := rows.Scan(&day, &count); err != nil {
			return nil, err
		}
		history = append(history, count)
	}
	stats["completion_history"] = history

	return stats, nil
}
