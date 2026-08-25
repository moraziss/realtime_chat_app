package ws

import (
	"Real-time-Chat/internal/pkg/token"
	"Real-time-Chat/internal/repository"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"github.com/gorilla/websocket"
	"github.com/julienschmidt/httprouter"
)

var errSendBufferFull = errors.New("ws: send buffer full, message dropped")

var (
	writeWait            = 10 * time.Second
	maxMessageSize int64 = 512
	pongWait             = 60 * time.Second
	pingPeriod           = (pongWait * 9) / 10

	defaultBroadcastQueueSize = 10000
)

// allowedWSOrigins задаётся один раз при старте через SetAllowedOrigins (см.
// cmd/app/main.go, значение приходит из config.Config.AllowedOrigins). Если
// не задано (nil), origin не проверяется — как и раньше.
var allowedWSOrigins map[string]struct{}

// SetAllowedOrigins задаёт множество разрешённых Origin для апгрейда
// WebSocket-соединения. Должна вызываться один раз при старте, до того как
// начнут приходить запросы на /ws.
func SetAllowedOrigins(origins map[string]struct{}) {
	allowedWSOrigins = origins
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		if len(allowedWSOrigins) == 0 {
			return true
		}
		_, ok := allowedWSOrigins[r.Header.Get("Origin")]
		return ok
	},
}

type Chat struct {
	broadcast chan Message
	quit      chan struct{}
	sessions  *Sessions
	lookup    *Table
	rooms     *Table // ← убираем TableInMemory, используем просто Table
	db        Repository
}

func New(db Repository) *Chat {
	c := Chat{
		broadcast: make(chan Message, defaultBroadcastQueueSize),
		quit:      make(chan struct{}),
		sessions:  NewSessions(),
		lookup:    NewTableInMemory(),
		rooms:     NewTableInMemory(),
		db:        db,
	}

	slog.Info("ws: event loop starting")
	go c.eventloop()

	return &c
}

func (c *Chat) Close() {
	c.quit <- struct{}{}
	close(c.quit)
	slog.Info("ws: stopped")
}

func (c *Chat) Broadcast(msg Message) error {
	users := c.rooms.GetUsers(msg.Receiver)
	var firstErr error
	for _, user := range users {
		sessions := c.lookup.Get(UserID(user))
		for _, sid := range sessions {
			sess := c.sessions.Get(sid)
			if sess == nil {
				continue
			}
			// Сама запись в соединение выполняется в Session.writePump —
			// здесь мы только кладём сообщение в очередь на отправку.
			if !sess.Send(msg) && firstErr == nil {
				firstErr = errSendBufferFull
			}
		}
	}
	return firstErr
}

// eventloop — единственная долгоживущая горутина, через которую проходят все
// WS-события. recover() здесь обязателен: без него один паникующий обработчик
// (например, неожиданный тип в metadata) убил бы обработку сообщений для
// вообще всех подключённых клиентов, а не только для одного отправителя.
// Восстанавливаемся и перезапускаем цикл, а не даём процессу упасть целиком.
func (c *Chat) eventloop() {
	defer func() {
		if r := recover(); r != nil {
			slog.Error("ws: event loop panic, restarting", "panic", r, "stack", string(debug.Stack()))
			go c.eventloop()
		}
	}()

	getStatus := func(user string) string {
		sessions := c.Get(UserID(user))
		if len(sessions) == 0 {
			return "0"
		}
		return "1"
	}

loop:
	for {
		select {
		case <-c.quit:
			slog.Info("ws: event loop stopped")
			break loop

		case msg, ok := <-c.broadcast:
			if !ok {
				break loop
			}

			slog.Debug("ws: message received", "type", msg.Type, "sender", msg.Sender, "receiver", msg.Receiver)

			// Отправитель должен состоять в комнате-получателе — иначе
			// любой клиент мог слать сообщения/менять задачи в чужих комнатах.
			if msg.Receiver != "" && !c.canAccessRoom(msg.Sender, msg.Receiver) {
				slog.Warn("ws: access denied", "sender", msg.Sender, "room", msg.Receiver, "type", msg.Type)
				continue
			}

			switch msg.Type {
			case MessageTypeStatus:
				msg.Text = getStatus(msg.Text)

			case MessageTypeAuth:
				msg.Text = msg.Sender

			case MessageTypeMessage:
				// Теперь мы передаем также метаданные (для файлов/фото)
				msgID, err := c.db.CreateConversationReply(msg.Sender, msg.Receiver, msg.Text, msg.Metadata)
				if err != nil {
					slog.Error("ws: failed to save message", "sender", msg.Sender, "receiver", msg.Receiver, "err", err)
					continue
				}
				msg.ID = msgID

			case MessageTypeTask:
				// Используем TaskStatus, если Flutter шлет статус именно в этом поле
				status := msg.TaskStatus
				if status == "" {
					status = msg.Text // Запасной вариант, если статус в поле data/text
				}

				slog.Debug("ws: updating task", "task_id", msg.TaskID, "status", status)

				err := c.db.UpdateTaskStatus(msg.TaskID, status, nil)
				if err != nil {
					slog.Error("ws: failed to update task", "task_id", msg.TaskID, "err", err)
					continue
				}

			case "read":
				slog.Debug("ws: messages marked read", "sender", msg.Sender, "room", msg.Receiver)
				err := c.db.MarkMessagesAsRead(msg.Receiver, msg.Sender)
				if err != nil {
					slog.Error("ws: failed to mark messages read", "room", msg.Receiver, "sender", msg.Sender, "err", err)
				}

			// --- НОВЫЙ БЛОК: Обработка "рукопожатия" для старта задачи ---
			case "task_accept":
				slog.Debug("ws: task accept requested", "task_id", msg.TaskID, "user", msg.Sender)

				// Обращаемся к новому методу БД, который мы написали
				updatedMeta, err := c.db.AcceptTask(msg.TaskID, msg.Sender)
				if err != nil {
					slog.Error("ws: failed to accept task", "task_id", msg.TaskID, "err", err)
					continue
				}

				// Упаковываем обновленные метаданные (нужен import "encoding/json" в начале файла)
				newMetaBytes, err := json.Marshal(updatedMeta)
				if err != nil {
					slog.Error("ws: failed to marshal task metadata", "task_id", msg.TaskID, "err", err)
					continue
				}

				// Меняем тип сообщения на task_sync, чтобы Flutter понял, что надо обновить UI
				msg.Type = "task_sync"
				msg.Metadata = newMetaBytes
			}

			// Рассылаем всем участникам комнаты
			c.Broadcast(msg)
		}
	}
}

// canAccessRoom сообщает, состоит ли пользователь userID в комнате roomID.
// Сначала проверяется быстрая in-memory таблица; если комнату туда ещё не
// подгрузили (например, она создана уже после подключения по WS), делаем
// разовую проверку в БД и, если членство подтвердилось, кэшируем его.
func (c *Chat) canAccessRoom(userID, roomID string) bool {
	for _, member := range c.rooms.GetUsers(roomID) {
		if member == userID {
			return true
		}
	}

	rooms, err := c.db.GetRoom(userID)
	if err != nil {
		slog.Error("ws: failed to check room access", "user_id", userID, "room_id", roomID, "err", err)
		return false
	}
	for _, r := range rooms {
		if r == roomID {
			c.rooms.AddRoom(roomID, userID)
			return true
		}
	}
	return false
}

func (c *Chat) newSession(ws *websocket.Conn) *Session {
	sess := NewSession(ws)
	c.sessions.Put(sess)
	return sess
}

func (c *Chat) Bind(uid UserID, sid SessionID) func() {
	slog.Debug("ws: binding session", "user_id", uid, "session_id", sid)

	if sess := c.Get(uid); len(sess) == 0 {
		c.Join(uid)
	}
	c.lookup.Add(uid.String(), sid.String())

	return func() {
		session := c.sessions.Get(sid.String())
		c.Clear(session)
		c.lookup.DeleteSession(sid)
		if len(c.Get(uid)) == 0 {
			c.Leave(uid)
		}
	}
}

func (c *Chat) ServeWS(signer token.Signer, repo repository.User) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		if r.Method != http.MethodGet {
			http.Error(w, "метод не разрешён", http.StatusMethodNotAllowed)
			return
		}

		ws, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		defer ws.Close()

		tok := r.URL.Query().Get("token")
		if tok == "" {
			ws.WriteMessage(websocket.TextMessage,
				websocket.FormatCloseMessage(websocket.CloseNormalClosure, "токен обязателен"))
			return
		}

		userID, err := signer.Verify(tok)
		if err != nil {
			ws.WriteMessage(websocket.TextMessage,
				websocket.FormatCloseMessage(websocket.CloseNormalClosure, "не авторизован"))
			return
		}

		_, err = repo.GetUser(userID)
		if err != nil {
			ws.WriteMessage(websocket.TextMessage,
				websocket.FormatCloseMessage(websocket.CloseNormalClosure, "пользователь не найден"))
			return
		}

		session := c.newSession(ws)
		closeFunc := c.Bind(UserID(userID), SessionID(session.SessionID()))
		defer closeFunc()

		ws.SetReadLimit(maxMessageSize)
		ws.SetReadDeadline(time.Now().Add(pongWait))
		ws.SetPongHandler(func(string) error {
			ws.SetReadDeadline(time.Now().Add(pongWait))
			return nil
		})

		for {
			var msg Message
			if err := ws.ReadJSON(&msg); err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway) {
					slog.Warn("ws: unexpected close", "user_id", userID, "err", err)
				}
				break
			}

			// Игнорируем join сообщения
			if msg.Type == "join" {
				continue
			}

			msg.Sender = userID
			c.broadcast <- msg
		}
	}
}

func (c *Chat) Join(uid UserID) {
	rooms, err := c.db.GetRooms(string(uid))
	if err != nil {
		slog.Error("ws: failed to load rooms", "user_id", uid, "err", err)
		return
	}
	for _, room := range rooms {
		c.broadcast <- Message{
			Type:     MessageTypePresence,
			Sender:   string(uid),
			Receiver: room.RoomID,
			Text:     MessageOnline,
		}
		c.rooms.AddRoom(room.RoomID, uid.String())
		slog.Debug("ws: user joined room", "user_id", uid, "room_id", room.RoomID)
	}
}

func (c *Chat) Leave(uid UserID) {
	onDelete := func(room string) {
		c.broadcast <- Message{
			Type:     MessageTypePresence,
			Sender:   string(uid),
			Receiver: room,
			Text:     MessageOffline,
		}
	}
	c.rooms.Delete(uid.String(), onDelete)
	slog.Debug("ws: user left all rooms", "user_id", uid)
}

func (c *Chat) Clear(sess *Session) {
	if sess == nil {
		return
	}
	sess.Close() // останавливает writePump
	sess.Conn().Close()
	sessionID := sess.SessionID()
	c.sessions.Delete(sessionID)
	slog.Debug("ws: session cleared", "session_id", sessionID)
}

func (c *Chat) Get(key interface{}) []*Session {
	switch v := key.(type) {
	case SessionID:
		sess := c.sessions.Get(v.String())
		if sess == nil {
			return nil
		}
		return []*Session{sess}
	case UserID:
		var result []*Session
		sessions := c.lookup.Get(key)
		for _, sid := range sessions {
			sess := c.sessions.Get(sid)
			if sess != nil {
				result = append(result, sess)
			}
		}
		return result
	default:
		return nil
	}
}
