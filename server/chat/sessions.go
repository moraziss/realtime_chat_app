package chat

import (
	"crypto/rand"
	"encoding/base64"
	"sync"

	"github.com/gorilla/websocket"
)

// Session представляет пользовательскую сессию.
// Один пользователь может иметь несколько сессий —
// с разных устройств (Windows, Android).
type Session struct {
	id   string
	conn *websocket.Conn
}

func NewSession(conn *websocket.Conn) *Session {
	return &Session{
		id:   randomString(32),
		conn: conn,
	}
}

func randomString(n int) string {
	b := make([]byte, n)
	_, err := rand.Read(b)
	if err != nil {
		return ""
	}
	return base64.StdEncoding.EncodeToString(b)
}

func (s *Session) Conn() *websocket.Conn {
	return s.conn
}

func (s *Session) SessionID() string {
	return s.id
}

// Sessions управляет всеми активными сессиями.
type Sessions struct {
	mu       sync.RWMutex
	sessions map[string]*Session
}

func NewSessions() *Sessions {
	return &Sessions{
		sessions: make(map[string]*Session),
	}
}

func (s *Sessions) Put(sess *Session) {
	s.mu.Lock()
	s.sessions[sess.id] = sess
	s.mu.Unlock()
}

func (s *Sessions) Get(id string) *Session {
	s.mu.RLock()
	sess, _ := s.sessions[id]
	s.mu.RUnlock()
	return sess
}

func (s *Sessions) Delete(id string) {
	s.mu.Lock()
	delete(s.sessions, id)
	s.mu.Unlock()
}
