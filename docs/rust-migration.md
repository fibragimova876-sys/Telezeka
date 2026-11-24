# Telezeka 0.3 — phased Rust migration

The new Axum/Tokio/SQLx core handles frequent authenticated read requests: GET /chats, /chats/{id}/messages, /incoming and /announcement. A read-only connection pool and combined SQL JSON queries reduce database round trips. Session hashes, expiry, banned-account and chat-membership checks match the existing API. All writes, registration, delivery, media, admin features and other routes are forwarded to the existing Python process on loopback. This is not a complete Rust rewrite yet. Benchmark and integration results are required before claiming a performance gain.

Dockerfile.rust packages both processes. The existing Dockerfile remains a rollback path. SQLite data stays on /data/chat.db. Keep credentials in Railway variables only.

CI: Rust core integration builds the core, runs Python access-control tests and compares authenticated Rust responses to Python responses, including blocked access, reactions, pins and a proxied write. Do not promote a failing build.

Railway: public HTTPS endpoint is telezeka-api-production.up.railway.app; source connection and deployment must succeed before it is usable. The application remains invite-only, including international phone/email registration. Real SMS and email require configured providers and country-specific delivery checks.

For a global production service, migrate to PostgreSQL, object storage, real-time WebSockets, background notifications, TURN relays with temporary credentials, regional deployment, backups, monitoring, and abuse controls. Multi-region SQLite replicas are not safe for shared chat writes. Preserve private chats and owner access rules. Add country-aware phone routing, localization, and privacy/account-deletion controls before public signup.