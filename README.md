# Real-time Chat

Мессенджер на Go с чатом в реальном времени по WebSocket, личными комнатами и совместными задачами (task-менеджер) внутри диалога.

![Go](https://img.shields.io/badge/Go-1.22-00ADD8?logo=go&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-4169E1?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![License](https://img.shields.io/badge/license-unspecified-lightgrey)

## Возможности

- Регистрация с подтверждением e-mail по коду и вход по JWT (access-токен).
- Личные комнаты (1:1) между пользователями, история сообщений с пагинацией.
- Обмен сообщениями и файлами (фото/вложения) в реальном времени через WebSocket.
- Присутствие пользователя в комнате (online/offline) и статус прочтения сообщений.
- Совместные задачи (task-менеджер) внутри чата: создание, назначение, приоритет, срок, подзадачи, принятие задачи обеими сторонами.
- Профиль пользователя (аватар, био, настройки) и персональная статистика по задачам.
- Загрузка файлов и раздача статики.

## Стек

| Слой          | Технология                                              |
|---------------|----------------------------------------------------------|
| Язык          | Go 1.22                                                   |
| HTTP-роутинг  | [`julienschmidt/httprouter`](https://github.com/julienschmidt/httprouter) |
| WebSocket     | [`gorilla/websocket`](https://github.com/gorilla/websocket) |
| База данных   | PostgreSQL 15 (`lib/pq`, JSONB для метаданных)            |
| Авторизация   | JWT (`golang-jwt/jwt/v5`), пароли — `bcrypt`              |
| Почта         | SMTP (коды подтверждения регистрации)                     |
| Инфраструктура| Docker / Docker Compose                                   |

## Архитектура

Проект организован по слоям в духе чистой архитектуры:

```
cmd/app            → точка входа, сборка зависимостей, роутинг
internal/
  entity/           → доменные модели (User, Task, Conversation, ...)
  controller/       → HTTP-хендлеры (транспортный слой)
  service/          → бизнес-логика, use-case'ы
  repository/       → интерфейсы доступа к данным
  database/         → реализация репозиториев поверх PostgreSQL
  ws/               → хаб WebSocket-соединений, комнаты, сессии
  pkg/
    token/          → выпуск и проверка JWT
    utils/          → хеширование, генерация кодов
migrations/         → SQL-схема БД
uploads/            → загруженные пользователями файлы
```

Каждый HTTP-хендлер получает сервис нужного use-case'а (замыкание с сигнатурой
`func(ctx, Request) (*Response, error)`), а сервис работает с БД через интерфейсы
пакета `repository`, что позволяет подменять реализацию в тестах.

## Быстрый старт

### Через Docker Compose (рекомендуется)

```bash
git clone <repo-url>
cd Real-time-Chat
cp .env.example .env   # заполните значения, см. раздел "Конфигурация"
make up
```

Сервер поднимется на `http://localhost:8080`, база данных — на `localhost:5432`.

Полезные команды:

```bash
make build   # docker-compose up --build
make logs    # логи сервера
make down    # остановить контейнеры
make psql    # зайти в psql внутри контейнера БД
```

### Локально (без Docker)

Потребуется установленный Go 1.22+ и доступный PostgreSQL с накатанной схемой из
[`migrations/init.sql`](migrations/init.sql).

```bash
go mod download
go run ./cmd/app
```

Переменные окружения читаются из `.env` (см. `Makefile`, цель `start`) либо из окружения процесса.

## Конфигурация

| Переменная      | Назначение                                   | Пример                  |
|------------------|-----------------------------------------------|--------------------------|
| `DB_USER`        | пользователь PostgreSQL                       | `user`                  |
| `DB_PASS`        | пароль PostgreSQL                             | `pass`                  |
| `DB_NAME`        | имя базы данных                               | `messenger`              |
| `DB_HOST`        | хост БД (по умолчанию `localhost`)            | `db`                     |
| `JWT_SECRET`     | секрет для подписи JWT                        | `change-me`              |
| `JWT_ISSUER`     | issuer в claims токена                        | `real-time-chat`         |
| `SMTP_HOST`      | SMTP-сервер для писем с кодом подтверждения   | `smtp.gmail.com`         |
| `SMTP_PORT`      | порт SMTP                                     | `587`                    |
| `SMTP_USER`      | адрес отправителя                             | `noreply@example.com`    |
| `SMTP_PASSWORD`  | пароль/app-password отправителя               | —                        |

> Файл `.env` содержит секреты и не должен попадать в систему контроля версий
> (уже добавлен в `.gitignore`).

## HTTP API

| Метод | Путь                        | Авторизация | Описание                                   |
|-------|-----------------------------|:-----------:|---------------------------------------------|
| GET   | `/health`                   | —           | Проверка живости сервиса                     |
| POST  | `/register/send-code`       | —           | Отправить код подтверждения на e-mail        |
| POST  | `/register`                 | —           | Регистрация по коду из письма                |
| POST  | `/login`                    | —           | Вход, выдаёт JWT                             |
| POST  | `/auth`                     | ✅          | Проверить токен, вернуть имя пользователя    |
| GET   | `/users`                    | ✅          | Список пользователей (для старта диалога)    |
| GET   | `/users/me`                 | ✅          | Текущий профиль                              |
| PUT   | `/users/me`                 | ✅          | Обновить профиль                             |
| DELETE| `/users/me`                 | ✅          | Удалить аккаунт                              |
| GET   | `/users/me/stats`           | ✅          | Статистика по задачам                        |
| GET   | `/users/me/extended-stats`  | ✅          | Расширенная статистика                       |
| GET   | `/rooms`                    | ✅          | Список комнат пользователя                   |
| POST  | `/rooms`                    | ✅          | Создать/получить личную комнату с другим юзером |
| GET   | `/conversations/:id`        | ✅          | История сообщений комнаты                    |
| GET   | `/rooms/:id/tasks`          | ✅          | Задачи комнаты                               |
| POST  | `/rooms/:id/tasks`          | ✅          | Создать задачу                               |
| PATCH | `/tasks/:id`                | ✅          | Обновить задачу/статус                       |
| DELETE| `/tasks/:id`                | ✅          | Удалить задачу                               |
| POST  | `/upload`                   | ✅          | Загрузить файл                               |
| GET   | `/uploads/*filepath`        | —           | Отдать загруженный файл                      |
| GET   | `/ws?token=<JWT>`           | ✅ (query)  | WebSocket-соединение                         |

Авторизованные запросы передают токен в заголовке `Authorization: Bearer <token>`.

## WebSocket-протокол

Сообщение — JSON-объект с полями `type`, `room` (id получателя/комнаты), `data`,
`task_id`, `task_status`, `metadata`, `timestamp`. Основные типы `type`:

- `message` — текстовое/файловое сообщение в комнату;
- `presence` — оповещение о статусе `online`/`offline`;
- `status` — запрос текущего статуса пользователя;
- `read` — отметка о прочтении сообщений в комнате;
- `task` — обновление статуса задачи из клиента;
- `task_accept` — «рукопожатие» принятия задачи участником;
- `task_created` / `task_updated` / `task_sync` — серверные события об изменении задач.

## Схема данных

Основные таблицы (см. [`migrations/init.sql`](migrations/init.sql)): `users`,
`rooms`, `user_rooms` (связь многие-ко-многим), `conversations` (сообщения,
включая метаданные задач в JSONB), `tasks`, `verification_codes`.

## Лицензия

Лицензия проекта не определена.
