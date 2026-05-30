# Auren Infrastructure — AI Agent Rules

> **Read the root `../AGENTS.md` FIRST for global rules.**

## Overview

Docker Compose setup for local development services.
Location: `docker/docker-compose.yml`

---

## Services

| Service | Image | Container | Port | Purpose |
|---|---|---|---|---|
| PostgreSQL | `postgres:16-alpine` | `auren-postgres` | `5432` | Main database |
| Redis | `redis:7-alpine` | `auren-redis` | `6379` | Cache |
| Keycloak | `keycloak:25.0` | `auren-keycloak` | `8180` | Identity provider (OAuth2/OIDC) |

All services run on the `auren-network` Docker bridge network.

---

## Credentials (development only)

### PostgreSQL
- Database: `auren`
- User: `auren_user`
- Password: `auren_dev_password`
- Init script: `docker/postgres/init.sql`

### Redis
- Password: `auren_redis_dev`

### Keycloak
- Admin user: `admin`
- Admin password: `admin`
- Realm: `auren` (imported from `docker/keycloak/realm-export.json`)
- External port: `8180` (mapped from container's `8080`)
- DB schema: `keycloak` (in the same PostgreSQL instance)

---

## ⛔ CRITICAL RULES

### 1. Credential Consistency

If you change any credential here, you MUST update:
- `auren-backend/src/main/resources/application.yml` (datasource, redis, keycloak config)
- `auren-cms/.env.local` (KEYCLOAK_ISSUER, NEXT_PUBLIC_API_URL)
- `auren-mobile/src/config.ts` (KEYCLOAK_REALM_URL)

### 2. Keycloak Realm

- The realm `auren` is auto-imported on first start from `docker/keycloak/realm-export.json`
- If you need to change Keycloak configuration (clients, roles, etc.), modify the realm export JSON and recreate the container
- Client IDs: `auren-cms` (CMS), `auren-mobile` (Mobile)
- **DO NOT** change client IDs without updating both frontend apps

### 3. PostgreSQL Schema

- Application data lives in the `auren` schema
- Keycloak data lives in the `keycloak` schema (same database)
- `docker/postgres/init.sql` creates the initial schemas
- **DO NOT** modify `init.sql` — it only runs on first container creation
- Database migrations are managed by Flyway in the backend (NOT here)

### 4. Service Dependencies

- Keycloak depends on PostgreSQL (waits for healthcheck)
- Backend depends on ALL three services (PostgreSQL, Redis, Keycloak)
- CMS and Mobile depend on Backend + Keycloak

### 5. Volume Persistence

- `postgres_data` — persists database data across restarts
- `redis_data` — persists cache data across restarts
- To reset everything: `docker-compose down -v` (removes volumes)

---

## Commands

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services (preserve data)
docker-compose down

# Full reset (destroy data)
docker-compose down -v

# Rebuild after config changes
docker-compose up -d --force-recreate
```
