# HomeSpace Server

HomeSpace backend service built with Node.js 22/24 LTS, Fastify, and native `node:sqlite`. Designed for lightweight, private, self-hosted family photo storage on local hardware (e.g., Xubuntu laptop).

## Features
- **Health check**: `GET /api/health` for connection validation and latency check.
- **Authentication**: `POST /api/auth/register`, `POST /api/auth/login`, `GET /api/auth/me`, `POST /api/auth/logout`.
- **Physical directory isolation**: Each registered user is provisioned a dedicated, isolated storage directory (`/users/<userId>/originals` and `/users/<userId>/thumbnails`).
- **Quota system**: Enforces per-user storage quotas (default: 10 GiB per user) to protect hardware disk capacity.
- **Media Pipeline**:
  - `POST /api/media/upload`: Multipart photo upload with quota validation & sharp thumbnail generation.
  - `GET /api/media`: Filter by favorites or timeline.
  - `GET /api/media/:id`: Strict access control (owner or shared album member only).
  - `GET /api/media/:id/thumb`: High-performance WebP thumbnail streaming.
  - `GET /api/media/:id/file`: Full resolution streaming with byte-range (`Range: bytes=...`) support.
  - `PATCH /api/media/:id`: Favorite toggle.
  - `POST /api/media/:id/trash` & `/restore`: Soft delete and recovery.
  - `DELETE /api/media/:id`: Permanent delete (unlinks files and frees storage quota).
  - Batch operations: `/api/media/batch/trash`, `/restore`, `/favorite`, `/delete`.
- **Albums & Family Sharing**:
  - `GET /api/albums`, `POST /api/albums`, `GET /api/albums/:id`, `PATCH /api/albums/:id`, `DELETE /api/albums/:id`.
  - Add/remove photos: `POST /api/albums/:id/media`, `DELETE /api/albums/:id/media/:mediaId`.
  - Member roles: `POST /api/albums/:id/members`, `PATCH /api/albums/:id/members/:userId`, `DELETE /api/albums/:id/members/:userId`.
- **Trash**: `GET /api/trash`, `POST /api/trash/empty` (permanent purge & quota restoration).

## Quick Start

```bash
# In the server folder:
corepack pnpm install
node --env-file-if-exists=.env src/index.js
```

Runs by default on port `8888`.
