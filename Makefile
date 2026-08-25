-include .env
export

start:
	go run ./cmd/app

up:
	docker-compose up -d

down:
	docker-compose down

build:
	docker-compose up --build

logs:
	docker-compose logs -f server

tidy:
	go mod tidy

test:
	go vet ./...
	go test ./... -race -cover

psql:
	docker exec -it real-time-chat-db-1 psql -U ${DB_USER} -d ${DB_NAME}