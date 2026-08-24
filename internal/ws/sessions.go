package ws

import (
	"crypto/rand"
	"encoding/base64"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Session представляет пользовательскую сессию.
// Один пользователь может иметь несколько сессий —
// с разных устройств (Windows, Android).
//
// Всё, что пишет в conn (обычные сообщения и ping), идёт только через
// writePump — gorilla/websocket не допускает конкурентную запись в одно
// соединение, а раньше пинг и рассылка сообщений писали в него из разных
// горутин одновременно.
type Session struct {
	id   string
	conn *websocket.Conn
	send chan Message
	done chan struct{}
}

func NewSession(conn *websocket.Conn) *Session {
	sess := &Session{
		id:   randomString(32),
		conn: conn,
		send: make(chan Message, 32),
		done: make(chan struct{}),
	}
	go sess.writePump()
	return sess
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

// Send ставит сообщение в очередь на отправку этой сессии; сама запись
// происходит в writePump. Если буфер переполнен (клиент не читает),
// сообщение отбрасывается — соединение всё равно будет закрыто по
// таймауту записи/пинга.
func (s *Session) Send(msg Message) bool {
	select {
	case s.send <- msg:
		return true
	default:
		return false
	}
}

// Close останавливает writePump; безопасно вызывать более одного раза.
func (s *Session) Close() {
	select {
	case <-s.done:
	default:
		close(s.done)
	}
}

// writePump — единственное место, которое пишет в conn: и обычные
// сообщения из Send, и ping-кадры по таймеру.
func (s *Session) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		s.conn.Close()
	}()

	for {
		select {
		case <-s.done:
			return

		case msg := <-s.send:
			s.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := s.conn.WriteJSON(msg); err != nil {
				return
			}

		case <-ticker.C:
			s.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := s.conn.WriteMessage(websocket.PingMessage, []byte{}); err != nil {
				return
			}
		}
	}
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
