package entity

// ContextKey represents the context key type.
type ContextKey string

func (c ContextKey) String() string {
	return string(c)
}

// ContextKeyUserID represents the user_id context key.
const ContextKeyUserID = ContextKey("user_id")

// ContextKeyRequestID represents the per-request correlation ID context key.
const ContextKeyRequestID = ContextKey("request_id")
