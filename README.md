# Real-Time Chat & Task Manager (Fullstack)

[English](#english-version) | [Русская версия](#русская-версия)

---

## English version

### Overview
This is a production-style fullstack project featuring a high-performance **Go** backend and a cross-platform **Flutter** mobile application. It combines real-time messaging with a collaborative task management system.

### Features
- **Real-time Messaging**: Instant communication via WebSockets.
- **Task Management**: Create, edit, and track tasks directly within chat rooms.
- **Verification System**: Secure registration with SMTP-based email verification.
- **Cross-Platform**: Mobile app for Android and iOS.
- **Production-Ready Backend**: Structured Go code with PostgreSQL, JWT, and monitoring.

### Tech Stack

#### Frontend (Mobile)
- **Framework**: Flutter
- **State Management**: Provider
- **UI**: flutter_chat_ui
- **Networking**: HTTP & WebSockets

#### Backend
- **Language**: Go 1.21+
- **Router**: httprouter / chi
- **Database**: PostgreSQL (Primary), Redis (Cache/PubSub)
- **Real-time**: Gorilla WebSocket
- **Auth**: JWT (JSON Web Tokens)
- **Observability**: Prometheus & Grafana

### Project Structure
```text
/
├── client/              # Flutter mobile application
│   ├── lib/             # Dart source code
│   └── pubspec.yaml     # Flutter dependencies
├── server/              # Go backend service
│   ├── controller/      # Request handlers
│   ├── service/         # Business logic
│   ├── database/        # Storage layer
│   └── main.go          # Entry point
└── README.md
```

---

## Русская версия

### Обзор
Это полнофункциональный fullstack-проект, включающий высокопроизводительный бэкенд на **Go** и кроссплатформенное мобильное приложение на **Flutter**. Проект объединяет мессенджер реального времени и систему управления совместными задачами.

### Основные возможности
- **Мессенджер в реальном времени**: Мгновенный обмен сообщениями через WebSockets.
- **Управление задачами**: Создание, редактирование и отслеживание статуса задач прямо в чате.
- **Система верификации**: Регистрация с подтверждением через Email (SMTP).
- **Кроссплатформенность**: Приложение для Android и iOS.
- **Production-ready бэкенд**: Структурированный код на Go с использованием PostgreSQL, JWT и систем мониторинга.

### Стек технологий

#### Frontend (Mobile)
- **Framework**: Flutter
- **State Management**: Provider
- **UI**: flutter_chat_ui (адаптированный)
- **Networking**: HTTP & WebSockets

#### Backend
- **Язык**: Go 1.21+
- **Роутер**: httprouter
- **БД**: PostgreSQL (Основная), Redis (Кэш/PubSub)
- **Real-time**: Gorilla WebSocket
- **Авторизация**: JWT (JSON Web Tokens)
- **Мониторинг**: Prometheus & Grafana

### Структура проекта
```text
/
├── client/              # Мобильное приложение (Flutter)
│   ├── lib/             # Исходный код Dart
│   └── pubspec.yaml     # Зависимости Flutter
├── server/              # Серверная часть (Go)
│   ├── controller/      # Обработчики запросов
│   ├── service/         # Бизнес-логика
│   ├── database/        # Уровень доступа к данным
│   └── main.go          # Точка входа
└── README.md
```

### Быстрый старт

#### Запуск сервера
1. Перейдите в `server/`
2. Настройте переменные окружения (DB_USER, DB_PASS, SMTP_USER и т.д.)
3. Выполните `go run main.go`

#### Запуск приложения
1. Перейдите в `client/`
2. Укажите IP сервера в `lib/config.dart`
3. Выполните `flutter pub get`
4. Запустите через `flutter run`
