#### Swampert | Agent Swarms

## Guía de instalación

Levanta la base de datos, el engine (API) y el client (dashboard) en local.

### Requisitos previos

- [Bun](https://bun.sh) (runtime y package manager de `swampert-engine` y `swampert-client`)
- [Docker](https://www.docker.com/) + Docker Compose (para Postgres)

### 1. Variables de entorno

Cada proyecto trae un `.env.sample` que sirve de plantilla. Copia cada uno a `.env.local` y completa los valores marcados como `<secure_password>`:

```sh
cp services/postgres/.env.sample services/postgres/.env.local
cp projects/swampert-engine/.env.sample projects/swampert-engine/.env.local
cp projects/swampert-client/.env.sample projects/swampert-client/.env.local
```

Puntos a tener en cuenta al completarlos:

- **`services/postgres/.env.local`**: define `POSTGRES_PASSWORD` (superusuario) y las contraseñas de los tres roles de aplicación (`POSTGRES_SAMPLER_PASSWORD`, `POSTGRES_RUNNER_PASSWORD`, `POSTGRES_BACKUPER_PASSWORD`). Estas se usan para crear los roles en el primer arranque del contenedor (ver `.claude/docs/database.md`).
- **`projects/swampert-engine/.env.local`**: `POSTGRES_SAMPLER_URL` y `POSTGRES_RUNNER_URL` deben usar las mismas contraseñas que pusiste arriba para `sampler` y `runner`. `JWT_SECRET` no puede quedar vacío. `CORS_ORIGIN` ya incluye `http://localhost:5173` (client) y `http://localhost:3000` (engine) por defecto.
- **`projects/swampert-client/.env.local`**: `VITE_API_BASE_URL` debe apuntar al engine (`http://localhost:3000/api` por defecto) — y ese origen debe estar en el `CORS_ORIGIN` del engine.

### 2. Levantar Postgres

Desde la raíz del repo:

```sh
docker compose up -d
```

Esto usa `compose.yml` (raíz), que incluye `services/postgres/compose.yml`. En el primer arranque contra un volumen vacío, el contenedor ejecuta automáticamente `services/postgres/scripts/00-bootstrap.sh`, que crea los tres roles de Postgres (`sampler`, `runner`, `backuper`) con las contraseñas que definiste en `services/postgres/.env.local`.

> Si vuelves a correr esto contra un volumen ya inicializado, el bootstrap no se re-ejecuta — es un paso único por volumen, no por arranque de contenedor.

### 3. Engine (`swampert-api`)

```sh
cd projects/swampert-engine
bun install
```

Aplica las migraciones (corre como el rol `sampler`, vía `POSTGRES_SAMPLER_URL`):

```sh
bun run drizz:migrate
```

(Opcional) Puebla datos de ejemplo (tenants, usuarios, swarms, agents, executions, reportes de los últimos 12 meses):

```sh
bun run drizz:seeding
```

Levanta el servidor:

```sh
bun run source/cmd/service.ts
```

Verifica que está arriba:

```sh
curl http://localhost:3000/api/health
```

### 4. Client (`swampert-client`)

En otra terminal:

```sh
cd projects/swampert-client
bun install
bun run dev
```

Abre `http://localhost:5173`.

### Resumen rápido

| Servicio | Comando | URL |
|---|---|---|
| Postgres | `docker compose up -d` (raíz) | `localhost:5432` |
| Engine | `bun run source/cmd/service.ts` (`projects/swampert-engine`) | `http://localhost:3000/api` |
| Client | `bun run dev` (`projects/swampert-client`) | `http://localhost:5173` |

Para detener Postgres: `docker compose down` (agrega `-v` solo si quieres borrar también los datos).
