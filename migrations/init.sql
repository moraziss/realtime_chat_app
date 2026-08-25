-- Расширение для генерации UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Таблица пользователей
CREATE TABLE IF NOT EXISTS users (
    id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name            VARCHAR(65)  NOT NULL UNIQUE,
    email           VARCHAR(255) NOT NULL UNIQUE,
    hashed_password VARCHAR(255) NOT NULL,
    avatar_url      TEXT,
    bio             TEXT,
    settings        JSONB DEFAULT '{}'::jsonb,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 2. Таблица комнат
CREATE TABLE IF NOT EXISTS rooms (
    id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name       VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 3. Таблица связи пользователей и комнат
CREATE TABLE IF NOT EXISTS user_rooms (
    user_id    UUID REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
    room_id    UUID REFERENCES rooms(id) ON UPDATE CASCADE ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_room UNIQUE (user_id, room_id)
);

CREATE INDEX IF NOT EXISTS idx_user_rooms ON user_rooms (user_id, room_id);

-- 4. Таблица сообщений (с полем metadata для задач)
CREATE TABLE IF NOT EXISTS conversations (
    id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    text       TEXT NOT NULL,
    user_id    UUID REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
    room_id    UUID REFERENCES rooms(id) ON UPDATE CASCADE ON DELETE CASCADE,
    metadata   JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversations_room ON conversations (room_id);

-- 5. Таблица задач
CREATE TABLE IF NOT EXISTS tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES users(id),
    assigned_to UUID REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'todo',
    priority VARCHAR(20) DEFAULT 'medium',
    due_date TIMESTAMP,
    subtasks JSONB DEFAULT '[]'::jsonb,
    accepted_by JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tasks_room ON tasks (room_id);

-- init.sql применяется Postgres-образом только при первом старте (пустой
-- volume), поэтому для уже существующих БД добавляем колонку отдельно и
-- идемпотентно — этот ALTER безопасно перезапускать.
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS accepted_by JSONB DEFAULT '[]'::jsonb;

-- Ускоряет поиск сообщения-носителя задачи по (metadata->>'task_id'),
-- который используется при удалении задачи и обновлении её "живых" данных
-- в истории переписки.
CREATE INDEX IF NOT EXISTS idx_conversations_metadata_task_id
    ON conversations ((metadata->>'task_id'));

-- Таблица для временных кодов регистрации
CREATE TABLE IF NOT EXISTS verification_codes (
    email VARCHAR(255) PRIMARY KEY,
    code VARCHAR(6) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Refresh-токены: хранится только SHA-256 хэш самого токена (64 hex-символа),
-- а не токен целиком — утечка таблицы не даёт восстановить действующие
-- токены. revoked_at ставится при ротации (см. /auth/refresh) и при логауте.
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens (token_hash);