# Real-time Chat & Task Manager

Монорепозиторий из двух частей: бэкенд на Go и клиент на Flutter (Android, Windows, web).

```text
/
├── client/   # Flutter-приложение — см. client/lib
└── server/   # Go-бэкенд (REST + WebSocket, PostgreSQL) — см. server/README.md
```

## Быстрый старт

Бэкенд и его конфигурация, API, WebSocket-протокол и схема БД подробно описаны в
[`server/README.md`](server/README.md) — начните оттуда:

```bash
cd server
cp .env.example .env   # заполнить значения
docker compose up --build
```

Клиент:

```bash
cd client
flutter pub get
flutter run -d windows   # или -d chrome, -d android и т.д.
```

Хост API для клиента задаётся в [`client/lib/config.dart`](client/lib/config.dart).

## Лицензия

Не определена.
