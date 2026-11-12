# HomeSpace Server

HomeSpace backend service built with Node.js 22/24 LTS, Fastify, and native `node:sqlite`. Designed for lightweight, private, self-hosted family photo storage on local hardware (e.g., Xubuntu laptop).

## Features
- **Health check endpoint**: `GET /api/health` for connection validation and latency check.
- **Authentication**: `POST /api/auth/register`, `POST /api/auth/login`, `GET /api/auth/me`, `POST /api/auth/logout`.
- **Physical directory isolation**: Each registered user is provisioned a dedicated, isolated storage directory (`/users/<userId>/originals` and `/users/<userId>/thumbnails`).
- **Quota system**: Enforces per-user storage quotas (default: 10 GiB per user) to protect hardware disk capacity.
- **Security**: Scrypt password hashing with unique salts, constant-time verification, SHA-256 hashed bearer tokens, rate limiting.

## Quick Start

```bash
# In the server folder:
corepack pnpm install
node --env-file-if-exists=.env src/index.js
```

Runs by default on port `8888`.
