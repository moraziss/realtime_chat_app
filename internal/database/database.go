package database

import (
	"database/sql"
	"fmt"
	"os"
	"time"

	_ "github.com/lib/pq"
)

type Conn struct {
	db *sql.DB
}

func New(user, pass, name string) (*Conn, error) {
	host := os.Getenv("DB_HOST")
	if host == "" {
		host = "localhost"
	}
	connStr := fmt.Sprintf(
		"user=%s password=%s dbname=%s host=%s sslmode=disable",
		user, pass, name, host,
	)
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(25)
	db.SetConnMaxLifetime(5 * time.Minute)
	if err := db.Ping(); err != nil {
		return nil, err
	}
	return &Conn{db: db}, nil
}

func (c *Conn) Close() error {
	return c.db.Close()
}

func (c *Conn) Ping() error {
	return c.db.Ping()
}
