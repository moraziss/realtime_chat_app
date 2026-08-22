package ws

import (
	"Real-time-Chat/internal/database"
	"Real-time-Chat/internal/pkg/token"
	"Real-time-Chat/internal/repository"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
	"github.com/julienschmidt/httprouter"
)

var (
	writeWait            = 10 * time.Second
	maxMessageSize int64 = 512
	pongWait             = 60 * time.Second
	pingPeriod           = (pongWait * 9) / 10

	defaultBroadcastQueueSize = 10000
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type Chat struct {
	broadcast chan Message
	quit      chan struct{}
	sessions  *Sessions
	lookup    *Table
	rooms     *Table // ← убираем TableInMemory, используем просто Table
	db        *database.Conn
}

func New(db *database.Conn) *Chat {
	c := Chat{
		broadcast: make(chan Message, defaultBroadcastQueueSize),
		quit:      make(chan struct{}),
		sessions:  NewSessions(),
		lookup:    NewTableInMemory(),
		rooms:     NewTableInMemory(),
		db:        db,
	}

	log.Println("ws: запуск event loop")
	go c.eventloop()

	return &c
}

func (c *Chat) Close() {
	c.quit <- struct{}{}
	close(c.quit)
	log.Println("ws: остановлен")
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
			if err := sess.Conn().WriteJSON(msg); err != nil {
				c.Clear(sess)
				if firstErr == nil {
					firstErr = err
				}
				continue
			}
		}
	}
	return firstErr
}

func (c *Chat) eventloop() {
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
			log.Println("ws: event loop остановлен")
			break loop

		case msg, ok := <-c.broadcast:
			if !ok {
				break loop
			}

			log.Printf("ws: тип=%s отправитель=%s получатель=%s\n",
				msg.Type, msg.Sender, msg.Receiver)

			switch msg.Type {
			case MessageTypeStatus:
				msg.Text = getStatus(msg.Text)

			case MessageTypeAuth:
				msg.Text = msg.Sender

			case MessageTypeMessage:
				// Теперь мы передаем также метаданные (для файлов/фото)
				msgID, err := c.db.CreateConversationReply(msg.Sender, msg.Receiver, msg.Text, msg.Metadata)
				if err != nil {
					log.Printf("ws: ошибка сохранения сообщения: %v\n", err)
					continue
				}
				msg.ID = msgID

			case MessageTypeTask:
				// Используем TaskStatus, если Flutter шлет статус именно в этом поле
				status := msg.TaskStatus
				if status == "" {
					status = msg.Text // Запасной вариант, если статус в поле data/text
				}

				log.Printf("Обновление задачи в БД: ID=%s, Status=%s", msg.TaskID, status)

				err := c.db.UpdateTaskStatus(msg.TaskID, status, nil)
				if err != nil {
					log.Printf("ws: ошибка обновления задачи: %v\n", err)
					continue
				}

			case "read":
				log.Printf("Чат: пользователь %s прочитал сообщения в комнате %s", msg.Sender, msg.Receiver)
				err := c.db.MarkMessagesAsRead(msg.Receiver, msg.Sender)
				if err != nil {
					log.Printf("ws: ошибка MarkMessagesAsRead: %v\n", err)
				}

			// --- НОВЫЙ БЛОК: Обработка "рукопожатия" для старта задачи ---
			case "task_accept":
				log.Printf("Принятие задачи: ID=%s, User=%s", msg.TaskID, msg.Sender)

				// Обращаемся к новому методу БД, который мы написали
				updatedMeta, err := c.db.AcceptTask(msg.TaskID, msg.Sender)
				if err != nil {
					log.Printf("ws: ошибка AcceptTask: %v\n", err)
					continue
				}

				// Упаковываем обновленные метаданные (нужен import "encoding/json" в начале файла)
				newMetaBytes, err := json.Marshal(updatedMeta)
				if err != nil {
					log.Printf("ws: ошибка маршалинга метаданных: %v\n", err)
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

func (c *Chat) newSession(ws *websocket.Conn) *Session {
	sess := NewSession(ws)
	c.sessions.Put(sess)
	return sess
}

func (c *Chat) Bind(uid UserID, sid SessionID) func() {
	log.Printf("ws: привязка пользователя=%s сессия=%s\n", uid, sid)

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

		go ping(ws)

		for {
			var msg Message
			if err := ws.ReadJSON(&msg); err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway) {
					log.Printf("ws: неожиданное закрытие: %v\n", err)
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

func ping(ws *websocket.Conn) {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		ws.Close()
	}()
	for range ticker.C {
		ws.SetWriteDeadline(time.Now().Add(writeWait))
		if err := ws.WriteMessage(websocket.PingMessage, []byte{}); err != nil {
			break
		}
	}
}

func (c *Chat) Join(uid UserID) {
	rooms, err := c.db.GetRooms(string(uid))
	if err != nil {
		log.Printf("ws: ошибка получения комнат: %v\n", err)
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
		log.Printf("ws: пользователь %s вошёл в комнату %s\n", uid, room.RoomID)
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
	log.Printf("ws: пользователь %s вышел из всех комнат\n", uid)
}

func (c *Chat) Clear(sess *Session) {
	if sess == nil {
		return
	}
	sess.Conn().Close()
	sessionID := sess.SessionID()
	c.sessions.Delete(sessionID)
	log.Printf("ws: сессия %s очищена\n", sessionID)
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
