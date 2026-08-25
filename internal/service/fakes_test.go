package service

import (
	"Real-time-Chat/internal/entity"
	"fmt"
	"time"
)

// fakeUserRepo implements repository.User in memory, for tests that need a
// full user lifecycle (register/login) rather than the narrow single-method
// interfaces already faked elsewhere in this package (see task_test.go).
type fakeUserRepo struct {
	byEmail map[string]entity.User
	byID    map[string]entity.User
	codes   map[string]string

	createErr    error
	saveCodeErr  error
	checkCodeErr error
}

func newFakeUserRepo() *fakeUserRepo {
	return &fakeUserRepo{
		byEmail: map[string]entity.User{},
		byID:    map[string]entity.User{},
		codes:   map[string]string{},
	}
}

func (f *fakeUserRepo) CreateUser(user *entity.User) error {
	if f.createErr != nil {
		return f.createErr
	}
	if user.ID == "" {
		user.ID = fmt.Sprintf("user-%d", len(f.byID)+1)
	}
	f.byEmail[user.Email] = *user
	f.byID[user.ID] = *user
	return nil
}

func (f *fakeUserRepo) UpdateUser(user *entity.User) error {
	f.byID[user.ID] = *user
	return nil
}

func (f *fakeUserRepo) DeleteUser(id string) error {
	delete(f.byID, id)
	return nil
}

func (f *fakeUserRepo) GetUser(id string) (*entity.User, error) {
	u, ok := f.byID[id]
	if !ok {
		return nil, entity.ErrUserNotFound
	}
	return &u, nil
}

func (f *fakeUserRepo) GetUserByEmail(email string) (entity.User, error) {
	u, ok := f.byEmail[email]
	if !ok {
		return entity.User{}, entity.ErrUserNotFound
	}
	return u, nil
}

func (f *fakeUserRepo) GetUsers(currentUserID string) ([]entity.User, error) {
	var out []entity.User
	for id, u := range f.byID {
		if id != currentUserID {
			out = append(out, u)
		}
	}
	return out, nil
}

func (f *fakeUserRepo) SaveVerificationCode(email, code string, expiresAt time.Time) error {
	if f.saveCodeErr != nil {
		return f.saveCodeErr
	}
	f.codes[email] = code
	return nil
}

func (f *fakeUserRepo) CheckVerificationCode(email, code string) (bool, error) {
	if f.checkCodeErr != nil {
		return false, f.checkCodeErr
	}
	stored, ok := f.codes[email]
	return ok && stored == code, nil
}

func (f *fakeUserRepo) DeleteVerificationCode(email string) error {
	delete(f.codes, email)
	return nil
}

// fakeRefreshTokenRepo implements repository.RefreshToken in memory.
type fakeRefreshTokenRepo struct {
	byHash    map[string]*entity.RefreshToken
	nextID    int
	createErr error
}

func newFakeRefreshTokenRepo() *fakeRefreshTokenRepo {
	return &fakeRefreshTokenRepo{byHash: map[string]*entity.RefreshToken{}}
}

func (f *fakeRefreshTokenRepo) CreateRefreshToken(t *entity.RefreshToken) error {
	if f.createErr != nil {
		return f.createErr
	}
	f.nextID++
	t.ID = fmt.Sprintf("rt-%d", f.nextID)
	t.CreatedAt = time.Now()
	cp := *t
	f.byHash[t.TokenHash] = &cp
	return nil
}

func (f *fakeRefreshTokenRepo) GetRefreshTokenByHash(hash string) (*entity.RefreshToken, error) {
	t, ok := f.byHash[hash]
	if !ok {
		return nil, entity.ErrRefreshTokenInvalid
	}
	cp := *t
	return &cp, nil
}

func (f *fakeRefreshTokenRepo) RevokeRefreshToken(id string) error {
	for _, t := range f.byHash {
		if t.ID == id {
			now := time.Now()
			t.RevokedAt = &now
		}
	}
	return nil
}

func (f *fakeRefreshTokenRepo) RevokeAllRefreshTokensForUser(userID string) error {
	for _, t := range f.byHash {
		if t.UserID == userID {
			now := time.Now()
			t.RevokedAt = &now
		}
	}
	return nil
}

// fakeEmailSender implements EmailSender.
type fakeEmailSender struct {
	sendErr error
	sentTo  []string
}

func (f *fakeEmailSender) SendVerificationCode(toEmail, code string) error {
	if f.sendErr != nil {
		return f.sendErr
	}
	f.sentTo = append(f.sentTo, toEmail)
	return nil
}
