package chat

import (
	"sync"
)

// Table представляет маппинг связи один-ко-многим.
type Table struct {
	mu   sync.RWMutex
	data map[interface{}]map[string]struct{}
}

func NewTableInMemory() *Table {
	return &Table{
		data: make(map[interface{}]map[string]struct{}),
	}
}

// Get возвращает slice строк для заданного ключа.
func (t *Table) Get(key interface{}) []string {
	items := t.get(key)
	if items == nil {
		return []string{}
	}
	result := make([]string, 0, len(items))
	for item := range items {
		result = append(result, item)
	}
	return result
}

func (t *Table) get(id interface{}) map[string]struct{} {
	t.mu.RLock()
	defer t.mu.RUnlock()
	items, _ := t.data[id]
	return items
}

// Add добавляет двустороннюю связь user ↔ session.
func (t *Table) Add(user, session string) {
	t.add(UserID(user), session)
	t.add(SessionID(session), user)
}

// AddRoom добавляет одностороннюю связь room → user.
// Используется для хранения участников комнаты.
func (t *Table) AddRoom(roomID, userID string) {
	t.add(RoomID(roomID), userID)
}

func (t *Table) add(a interface{}, b string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if _, exist := t.data[a]; !exist {
		t.data[a] = make(map[string]struct{})
	}
	t.data[a][b] = struct{}{}
}

// GetUsers возвращает всех пользователей в комнате.
// Используется в Broadcast когда нужно разослать сообщение.
func (t *Table) GetUsers(roomID string) []string {
	return t.Get(RoomID(roomID))
}

// DeleteSession удаляет сессию и её связь с пользователем.
func (t *Table) DeleteSession(sid SessionID) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	if users, exist := t.data[sid]; exist {
		for user := range users {
			delete(t.data[UserID(user)], sid.String())
			if len(t.data[UserID(user)]) == 0 {
				delete(t.data, UserID(user))
			}
		}
	}
	delete(t.data, sid)
	return nil
}

// Delete удаляет пользователя из всех комнат.
// onDelete вызывается для каждой комнаты из которой удаляется пользователь.
func (t *Table) Delete(userID string, onDelete func(room string)) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	rooms, exist := t.data[UserID(userID)]
	if !exist {
		return nil
	}

	for room := range rooms {
		if onDelete != nil {
			onDelete(room)
		}
		// Удаляем пользователя из комнаты
		delete(t.data[RoomID(room)], userID)
		if len(t.data[RoomID(room)]) == 0 {
			delete(t.data, RoomID(room))
		}
	}

	delete(t.data, UserID(userID))
	return nil
}
