package service

import (
	"errors"
	"testing"
)

type fakeRoomLister struct {
	rooms map[string][]string
	err   error
}

func (f fakeRoomLister) GetRoom(userID string) ([]string, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.rooms[userID], nil
}

func TestIsRoomMember(t *testing.T) {
	rooms := fakeRoomLister{rooms: map[string][]string{
		"user-1": {"room-a", "room-b"},
	}}

	if !isRoomMember(rooms, "user-1", "room-a") {
		t.Error("isRoomMember() = false, want true for a room the user belongs to")
	}
	if isRoomMember(rooms, "user-1", "room-z") {
		t.Error("isRoomMember() = true, want false for a room the user doesn't belong to")
	}
	if isRoomMember(rooms, "user-2", "room-a") {
		t.Error("isRoomMember() = true, want false for a user with no rooms")
	}
}

func TestIsRoomMemberPropagatesLookupFailureAsDenied(t *testing.T) {
	rooms := fakeRoomLister{err: errors.New("boom")}

	if isRoomMember(rooms, "user-1", "room-a") {
		t.Error("isRoomMember() = true, want false when the room lookup fails")
	}
}
