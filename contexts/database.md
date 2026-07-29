# Swampert — Provisioning de Base de Datos

> Qué correr contra una instancia de Postgres nueva para que quede lista para recibir migraciones: convenciones de esquema, la única extensión requerida, los tres roles de Postgres, el patrón de Row-Level Security que protege el aislamiento multi-tenant, y cómo se separan modelado y permisos en las migraciones. Precede a cualquier migración de dominio, y aplica igual sin importar dónde corra la instancia — desarrollo local o producción.

---

## 🧱 Convenciones de esquema

Swampert organiza sus tablas en **tres schemas**, cada uno con una razón de ser distinta y ninguna superposición entre ellos:

| Schema | Contiene | Por qué está separado |
|---|---|---|
| `auth` | `tenants` (el tenant), `users` | Identidad: quién es cada empresa cliente y quién puede autenticarse dentro de ella. `tenants` es la raíz del aislamiento multi-tenant — todo lo demás cuelga de ahí. |
| `core` | `swarms`, `agents`, `tasks`, `executions` | El dominio de negocio estable: qué existe (enjambres, agentes, tareas) y qué se ejecutó. Cambia con la misma cadencia que el resto del modelo. |
| `trace` | `execution_steps`, `token_costs`, `execution_errors`, `audit_log` | Todo lo que crece sin parar y existe para observar: el detalle paso a paso de una ejecución, su costo, sus errores, y la auditoría de cambios de configuración. Es el schema con mayor volumen y el candidato natural a particionamiento (ver `concepts.md` § Particionamiento). |

Dos reglas de aislamiento multi-tenant, sencillas pero sin excepción:

- **`tenants` no lleva `tenant_id`.** Es la raíz del aislamiento, no un recurso que pertenece a un tenant — todo lo demás sí lo lleva.
- **El resto de las tablas tenant-scoped llevan `tenant_id NOT NULL`** referenciando `auth.tenants.id`. Son 9 en total: `auth.users`, las 4 de `core`, y las 4 de `trace`. Las de `trace` lo llevan denormalizado (no resuelto vía `JOIN` a `executions`) por la misma razón de rendimiento de RLS que documenta `concepts.md` § Row-Level Security.

### Tipos y patrones de columna

Tres convenciones se repiten en las 10 tablas del modelo, sin excepción:

| Convención | Regla | Por qué |
|---|---|---|
| **Identificadores** | `UUID` como PK, con `DEFAULT extensions.gen_random_uuid()` | En un sistema multi-tenant, un ID secuencial (`SERIAL`/`BIGSERIAL`) filtra volumen de negocio de otras empresas clientes del mismo sistema — cualquiera puede estimar cuántas filas existen contando gaps entre IDs propios. `gen_random_uuid()` lo provee la extensión `pgcrypto` (ver siguiente sección). |
| **Fechas y horas** | `TIMESTAMPTZ`, nunca `TIMESTAMP` a secas | `TIMESTAMPTZ` guarda el instante real (normalizado a UTC internamente) y lo convierte a la zona del cliente al leer. `TIMESTAMP` sin zona horaria es ambiguo apenas hay más de una zona involucrada — servidor, backend, usuario final — y ese es exactamente el caso acá. |
| **Borrado** | `ON DELETE RESTRICT` en toda FK + soft delete vía `deleted_at TIMESTAMPTZ NULL` | `RESTRICT` hace que borrar una fila con dependientes falle explícitamente en vez de arrastrar borrados en cascada silenciosos. El soft delete es el mecanismo real para "eliminar" desde la aplicación: se setea `deleted_at`, la fila nunca desaparece físicamente, y las consultas de la app filtran `WHERE deleted_at IS NULL`. Entre los dos, el modelo nunca pierde historia de forma irreversible ni por accidente. |

---

## 🧩 Extensión requerida

Swampert necesita una única extensión, habilitada en la primera migración antes de crear una sola tabla:

| Extensión | Para qué | Disponibilidad |
|---|---|---|
| `pgcrypto` | Funciones criptográficas: `crypt()`/`gen_salt('bf')` para el hash bcrypt de `auth.users.password_hash` (ver `concepts.md` § Cifrado de datos sensibles), y `gen_random_uuid()` como `DEFAULT` de toda PK. | Parte de `contrib`, incluida en la imagen oficial `postgres` — sin pasos adicionales, sin imagen custom ni `Dockerfile` propio. |

```sql
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA extensions;
```

No hay ninguna otra extensión en el modelo — a diferencia de proyectos que necesitan búsqueda semántica o full-text, Swampert no tiene ese requisito, así que la imagen oficial de Postgres alcanza sin modificaciones.

---

## 🧬 Migraciones: modelado y permisos por separado

Las migraciones son archivos `.sql` planos y numerados (`NNNN-descripcion.sql`), aplicados por el runner propio (`scripts/run_migrations.py`) con idempotencia por nombre de archivo y una transacción independiente por migración — nada de esto cambia acá, es la convención ya establecida.

**Lo que sí se adopta del provisioning de Kelsen: cada cambio de schema se separa en (al menos) dos migraciones — modelado (DDL) y permisos (DCL).** En vez de una sola migración que crea tablas y otorga privilegios en el mismo archivo, el patrón es:

```sql
-- 0004-modeling-core.sql: solo estructura
CREATE SCHEMA "core";
CREATE TABLE "core"."swarms" ( ... );
CREATE TABLE "core"."agents" ( ... );
-- ... resto de tablas y constraints de core

-- 0005-granting-core.sql: solo permisos, sobre lo que ya existe
GRANT USAGE ON SCHEMA core TO runner;
GRANT SELECT ON ALL TABLES IN SCHEMA core TO runner;
ALTER DEFAULT PRIVILEGES FOR ROLE sampler IN SCHEMA core
  GRANT SELECT ON TABLES TO runner;
```

**Por qué separarlo:** deja el cambio estructural (qué existe) y el cambio de permisos (quién puede tocarlo) como dos unidades revisables por separado, con el historial de grants auditable por sí mismo — un cambio que solo ajusta privilegios no se mezcla con uno que agrega una columna. Es una convención de trabajo, no una regla rígida: el nombre exacto (`modeling-<feature>` / `granting-<feature>`) puede ajustarse, lo que se mantiene es la idea de fondo — **DDL y DCL no comparten migración.**

---

## 🔐 Roles de Postgres

Swampert usa tres roles, cada uno con un propósito y un privilegio distinto:

| Rol | Propósito | Privilegios | Dónde corre |
|---|---|---|---|
| `sampler` | Dueño de los tres schemas de Swampert y de todos sus objetos. Aplica todas las migraciones, modelado y permisos por igual. | Único rol con `CREATE` sobre la base `swampert` — todo lo que crea (schemas, tablas, funciones) queda automáticamente de su propiedad. Bypassea RLS por ser owner — precisamente por eso nunca sirve tráfico. | Exclusivamente el runner de migraciones, nunca en el proceso de aplicación. |
| `runner` | El único rol con el que corre el backend. | `SELECT` sobre las tablas de los tres schemas, más `EXECUTE` sobre los procedimientos y funciones de `core`/`trace` — nunca `INSERT`/`UPDATE`/`DELETE` directo. `NOBYPASSRLS` explícito. | El backend (ElysiaJS), en cualquier ambiente. |
| `backuper` | Respaldo periódico de la base completa. | Únicamente `CONNECT` + los privilegios que exige `pg_dump` para leer el esquema y los datos. Sin `INSERT`/`UPDATE`/`DELETE`, sin `EXECUTE`. `NOBYPASSRLS` explícito. | El proceso de backup, nunca el backend ni un humano interactivo. |

### Provisioning en dos capas: bootstrap manual + migraciones de granting

Los tres roles **no** se crean con una migración — hay un problema de huevo-y-gallina: el runner de migraciones se conecta como `sampler`, así que `sampler` tiene que existir *antes* de que la primera migración pueda correr. Por eso se crean una sola vez, a mano, contra la instancia nueva, con [`projects/swampert-engine/drizzle/bootstrap.sql`](../projects/swampert-engine/drizzle/bootstrap.sql) — aplicado con una conexión de superusuario (o de administrador de la instancia), nunca con el runner ni con ninguno de los tres roles que crea:

```sql
-- Roles, creados de forma idempotente (seguro re-correr el script)
CREATE ROLE sampler  WITH LOGIN PASSWORD '...' NOBYPASSRLS;
CREATE ROLE runner   WITH LOGIN PASSWORD '...' NOBYPASSRLS;
CREATE ROLE backuper WITH LOGIN PASSWORD '...' NOBYPASSRLS;

-- Los tres pueden conectarse y usar pgcrypto...
GRANT USAGE ON SCHEMA extensions TO sampler, runner, backuper;
GRANT CONNECT ON DATABASE swampert TO sampler, runner, backuper;

-- ...pero solo sampler puede crear objetos nuevos
GRANT CREATE ON DATABASE swampert TO sampler;
```

Notar lo que `bootstrap.sql` **no** hace: no crea `auth`/`core`/`trace`, ni le da a `runner` o `backuper` ni un solo privilegio sobre esos schemas. Es a propósito — el bootstrap solo resuelve el arranque (que los roles existan y que `sampler` pueda crear cosas). Todo lo demás pasa después, ya con las migraciones corriendo:

1. **Ownership por creación, no por `AUTHORIZATION` explícito.** Como solo `sampler` tiene `CREATE` sobre la base, cada `CREATE SCHEMA`/`CREATE TABLE` de una migración de modelado (`000N-modeling-*.sql`) queda automáticamente de su propiedad — el dueño de un objeto en Postgres es quien ejecuta la sentencia que lo crea, y quien ejecuta las migraciones siempre es `sampler`.
2. **El acceso de `runner` y `backuper` se otorga recién en las migraciones de granting** (`000N-granting-*.sql`, ver sección anterior). Hasta que esa migración corre, ninguno de los dos puede ver una sola fila de `auth`/`core`/`trace`, aunque ya puedan conectarse a la base desde el bootstrap.

En otras palabras: **el ownership es todo de `sampler` desde el bootstrap, y el acceso de los demás roles se construye migración a migración, nunca de una sola vez.**

**Por qué `runner` no tiene `INSERT`/`UPDATE`/`DELETE` directo:** Proyecto II exige que toda escritura de negocio pase por un procedimiento almacenado que valida y transacciona — no por una sentencia suelta del backend. En vez de otorgarle a `runner` privilegios de escritura directa sobre las tablas (que le permitirían saltarse esa validación desde cualquier endpoint), los procedimientos y funciones de `core`/`trace` se definen como `SECURITY DEFINER`, propiedad de `sampler`. `runner` solo necesita `EXECUTE` sobre ellos: la única forma de escribir en la base, desde el backend, es invocando un procedimiento — nunca un `INSERT` directo. Esto no es solo un detalle de seguridad, es lo que hace que el requisito académico ("todo el flujo pasa por un procedimiento") sea estructuralmente cierto y no solo una convención que alguien podría no respetar.

**Reglas de uso, no negociables:**

- `sampler` corre exclusivamente al aplicar migraciones — nunca en el proceso del backend ni en el del backup.
- `runner` es la única credencial en las variables de entorno del backend.
- `backuper` es la única credencial del proceso de respaldo — nunca se usa para depurar ni para consultas manuales.
- Ningún rol tiene `BYPASSRLS`. Si en el futuro se necesita un proceso que cruce datos entre empresas (ej. un reporte agregado de toda la plataforma), se resuelve con una función `SECURITY DEFINER` explícita y auditada — nunca dándole `BYPASSRLS` a un rol de conexión general.
- `ALTER DEFAULT PRIVILEGES` se ejecuta con `sampler`, para que cualquier tabla o función nueva creada por una migración futura herede automáticamente los permisos correctos.

---

## 🛡️ Row-Level Security: patrón de aplicación

RLS con `FORCE` es, acá, el mecanismo central de aislamiento — no una segunda capa redundante. Como los procedimientos y funciones corren `SECURITY DEFINER` con `sampler` como owner (sección anterior), sin `FORCE ROW LEVEL SECURITY` el propio owner bypassearía la política al ejecutar la lógica de negocio, y el aislamiento entre empresas dejaría de existir en la práctica aunque la política exista en el catálogo.

Cada una de las 9 tablas tenant-scoped (`auth.users`, las 4 de `core`, las 4 de `trace`) sigue el mismo patrón de tres pasos:

```sql
ALTER TABLE <schema>.<tabla> ENABLE ROW LEVEL SECURITY;
ALTER TABLE <schema>.<tabla> FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON <schema>.<tabla>
  USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE POLICY backup_read ON <schema>.<tabla>
  FOR SELECT TO backuper
  USING (true);
```

- `auth.tenants` no lleva política de tenant — es la raíz del aislamiento, no un recurso perteneciente a un tenant.
- `tenant_id NOT NULL` va como columna líder en los índices compuestos de toda tabla tenant-scoped, porque toda query real ya llega filtrada por empresa.
- El segundo argumento `true` de `current_setting(...)` (`missing_ok`) es obligatorio: sin él, una sesión sin `app.current_tenant_id` seteado (como `backuper` corriendo `pg_dump`) hace que la función lance una excepción en vez de devolver `NULL`, y esa excepción aborta la consulta antes de que la política `backup_read` tenga oportunidad de otorgar acceso vía `OR`. Con `missing_ok`, `tenant_isolation` simplemente evalúa a `NULL`/falso para esa sesión y `backup_read` toma el control.

### `SET LOCAL`, nunca `SET SESSION`

El contexto de tenant se fija **dentro de la misma transacción** en la que corre el procedimiento o la consulta:

```sql
BEGIN;
SET LOCAL app.current_tenant_id = '<uuid de la empresa autenticada>';
-- CALL a un procedimiento, o SELECT de lectura
COMMIT;
```

`SET SESSION` se queda pegado a la conexión física si el backend usa connection pooling en modo transacción — un fallo de aislamiento real entre empresas, no teórico, si esa conexión se reutiliza para otro tenant. `SET LOCAL` se limpia al cierre de la transacción sin importar el pooling. Este `BEGIN` → `SET LOCAL` → `CALL`/`SELECT` → `COMMIT` se implementa como wrapper de transacción explícito en el backend, nunca como responsabilidad de cada endpoint por separado.