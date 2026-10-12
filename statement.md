# statement.md — Pipeline ETL con prácticas DataOps (reconciliado)

**Curso:** ISW-623 Bases de Datos Avanzadas · **Investigación 2** · **Responsable de la demo:** Roney
**Stack:** uv · Python 3.12 · pandas · pandera · structlog · PostgreSQL 17 · Docker Compose · pytest + hypothesis · GitHub Actions

> Este documento es la referencia de decisiones del proyecto. **El código real se escribe en `project/` y es la fuente de verdad**, no este documento.
>
> **Qué está verificado y qué no:**
> - Verificado en un entorno aislado (uv 0.12.1, Python 3.14, Docker 29.8 instalado): `pandas 3.0.6`, `pandera 0.34.1` y `structlog 26.1.0` importan y funcionan juntas. Un prototipo de validación con pandera confirmó: BOM, línea en blanco, varios motivos por fila, duplicado, cantidad cero, fecha imposible y precio cero se rechazan con el motivo esperado.
> - Verificado también: el `compose.yml` raíz con `include` del compose de `database` y `env_file` resuelve con `docker compose --profile etl config`; el paquete namespace `source` (sin `__init__.py`) con `uv_build` instala, ejecuta `uv run piper` y empaqueta `schema.sql` (§8).
> - **No ejecutado todavía:** `docker compose`, el `Dockerfile`, el workflow de GitHub Actions, la carga a PostgreSQL, `on_bad_lines` con función (§5.1) ni la suite de pruebas. Nada de esto se declara como hecho hasta verlo correr. Las capturas finales salen de la ejecución real.

---

## 1. Qué pide el enunciado y dónde lo cubrimos

| Criterio de aceptación | Evidencia esperada | Cómo lo cubrimos |
|---|---|---|
| Arranque | `docker compose up -d`, contenedores en ejecución | `project/compose.yml` con el servicio `database` + healthcheck (§8) |
| Ejecución válida | Conteos entrada / válidos / rechazados / cargados concuerdan | `piper run data/sales_valid.csv`; la conciliación (§5.5) se verifica contra la BD y la corrida falla si no cuadra |
| Consulta de destino | `SELECT COUNT(*)` + muestra de filas | Tabla `sales` (§6) |
| Calidad de datos | Inválido rechazado/aislado, **sin carga silenciosa** | Cuarentena en `rejected_records` + CSV de rechazados con motivos |
| Pruebas | pytest con número real de pruebas | Unitarias + integración + propiedades (§9); el número sale de pytest, no de este documento |
| Integración continua | Captura real de GitHub Actions | `.github/workflows/ci.yml` (§10). Si no se logra, se declara como limitación |
| Reproducibilidad | README con requisitos y comandos desde cero | §11 es el README |

Entregables a Iván: carpeta/repo con `project/compose.yml`, scripts, pruebas, `pyproject.toml` + `uv.lock` (sin `requirements.txt`, ver §8) y README; diagrama (§4); capturas numeradas (§12, fuera del repo); tabla de resultados reales (§12); explicación de 1–2 párrafos (§13); limitaciones (§14).

---

## 2. Idea general y decisiones de diseño

Un CSV de 1 000 ventas sintéticas entra a un pipeline en Python que **extrae → valida → transforma → carga** a PostgreSQL. Lo que lo hace "DataOps" y no "un script": corre en contenedores reproducibles, tiene pruebas automáticas, se ejecuta solo en CI, deja **auditoría de cada corrida** y **nunca pierde ni carga filas en silencio**.

| Decisión | Por qué |
|---|---|
| **uv** con `pyproject.toml` + `uv.lock` | El lockfile fija versiones exactas. `uv sync --locked` falla si el lock está desactualizado. No se mantiene `requirements.txt` (§8) |
| **pandas ≥ 3.0, < 4** | Última versión estable mayor al momento de escribir (3.0.6 probada). Se lee todo como **texto** (`dtype=str`) para no coaccionar valores antes de validar. Rango fijado por el lock; cambiarlo exige volver a correr la suite |
| **pandera** | Las reglas de calidad se declaran como un esquema con un `Check` **nombrado** por regla; el nombre es el código de rechazo. `validate(lazy=True)` reporta todos los fallos de golpe y de ahí salen los motivos por fila |
| **structlog** | Reemplaza una clase de logging propia. `run_id` se vincula una vez y viaja en cada evento; salida legible en consola y JSON Lines en archivo |
| **hypothesis** (dev) | Prueba de propiedades de la invariante central: para cualquier entrada, `válidas + rechazadas = entrada` |
| **Cuarentena + carga parcial** | Un dato malo no frena los buenos, pero tampoco desaparece: queda aislado con sus motivos |
| **Circuit breaker** (`MAX_REJECT_RATE`, 20 %) | Si se rechaza más del 20 %, la fuente probablemente está rota: la corrida **FALLA y no carga nada** |
| **Carga idempotente** (`ON CONFLICT DO NOTHING`) | Repetir el archivo no duplica filas. Idempotencia por **id**, no por contenido (§14) |
| **Carga en una transacción + conciliación contra la BD** | Si el estado real de la BD no coincide con los conteos, rollback |
| **Fecha solo ISO `YYYY-MM-DD`** | `03/04/2025` es ambiguo; adivinar es peor que rechazar |
| **Duplicados: gana la primera aparición** | Regla simple, determinista y documentada (límite en §14) |
| **`Decimal` para importes** | Sin ruido de punto flotante; `NUMERIC(…,2)` en la BD |
| **Rangos de negocio explícitos** | Cantidad y precio con tope, alineados a los tipos de la BD, para que un valor absurdo se **rechace** en vez de reventar el INSERT y tumbar el lote (§5.1) |
| **Reportes** | Tablas `etl_runs` y `rejected_records` como fuente de verdad; `run_<id>.json` y `rejected_<id>.csv` como evidencia portable; resumen en markdown por stdout (CI lo anexa al job summary) |
| **Seguridad por defecto** | Ver §7 |

---

## 3. Conceptos para explicar

- **ETL vs ELT:** ETL transforma *antes* de cargar; se eligió porque el requisito es *rechazar antes* de que el dato toque la tabla destino.
- **DataOps:** prácticas de DevOps aplicadas a pipelines de datos: control de versiones, pruebas automáticas, CI, entornos reproducibles, observabilidad y calidad de datos como parte del proceso.
- **Idempotencia:** ejecutar N veces deja el mismo resultado que una. Clave para reintentos seguros.
- **Cuarentena (dead-letter):** los inválidos se apartan con su motivo en vez de descartarse o cargarse.
- **Conciliación:** comprobación de que los conteos informados coinciden con lo que realmente hay en la BD (§5.5).
- **Observabilidad:** *logs* (evento por evento), *reporte de corrida* (resumen final), *tabla de auditoría* (historial consultable con SQL).
- **Data contract:** el esquema pandera es una declaración legible y versionada de lo que se acepta.
- **Pirámide de pruebas:** unitarias (sin BD), propiedades (hypothesis), integración (PostgreSQL real, `@pytest.mark.integration`).
- **Healthcheck + `depends_on: service_healthy`:** el ETL no arranca hasta que PostgreSQL acepta conexiones.
- **Compose profiles:** el servicio `etl` (definido en el compose raíz) está en el profile `etl`; `docker compose up -d` levanta solo la BD y el pipeline se lanza con `docker compose run`.

---

## 4. Arquitectura y flujo

```
   data/sales_valid.csv ─┐
   data/sales_invalid.csv┘
            │  (volumen montado)
            ▼
 ┌─────────── contenedor etl (Python + uv, bajo demanda) ───────────┐
 │  extract ─► validate ─┬─► transform ─► load ──► [conciliación]   │
 │  (todo texto)         │                 │            │           │
 │                       └─► rechazados    │            ▼           │
 │                          (cuarentena)   │       RunReport        │
 └───────────────────────┬─────────────────┼────────────┬───────────┘
                         ▼                 ▼            ▼
                 ┌─────────── contenedor database (PostgreSQL 17) ──┐   reports/ run_<id>.json
                 │ rejected_records   sales        etl_runs   │   reports/ rejected_<id>.csv
                 └────────────────────────────────────────────┘   logs/    etl_<id>.jsonl
                                                                  stdout:   resumen markdown

   GitHub Actions (push/PR): uv sync --locked → ruff → pytest (+service Postgres) → corrida E2E → resumen al job summary
```

Orden de una corrida: crear esquema si no existe → registrar la corrida como `RUNNING` (si el proceso muere, queda rastro) → extract → validate → rechazados a cuarentena → chequeo del umbral → transform → carga + conciliación en una transacción → estado final (`SUCCESS`, `SUCCESS_WITH_REJECTS` o `FAILED`) → actualizar `etl_runs` → escribir reportes.

---

## 5. Reglas, reportes y logging (compartir con Iván e Ian **antes** de implementar)

### 5.1 Lectura y reglas de validación

**Lectura** (`extract`):
- `pd.read_csv(..., dtype=str, keep_default_na=False, encoding="utf-8-sig", skip_blank_lines=False)`. `utf-8-sig` tolera el BOM de Excel; `skip_blank_lines=False` hace que una línea vacía llegue como fila y se rechace, en lugar de desaparecer.
- Filas con columnas de más o de menos: se pretende rechazarlas con `wrong_column_count` mediante `on_bad_lines` con función (requiere motor `python`). **Por verificar al implementar**; si no es viable, la corrida falla con un error claro (nunca en silencio).
- Columnas extra en el CSV: se ignoran y se registra el evento `extra_columns` con sus nombres. Faltan columnas requeridas → `SchemaError`.
- Tamaño máximo de archivo (`MAX_INPUT_MB`, default 50): mayor → falla antes de leerlo.
- `record_number` = posición del registro + 2 (encabezado = 1). Coincide con la línea del archivo salvo que haya campos multilínea entre comillas; se documenta.

**Reglas** (cada una es un `Check` pandera cuyo `name` es el código):

| Código de rechazo | Regla |
|---|---|
| `wrong_column_count` | La fila no tiene el número de columnas del encabezado |
| `missing_<campo>` | Campo obligatorio vacío o solo espacios (los 7 campos) |
| `invalid_transaction_id` | No es entero positivo de hasta 18 dígitos `[0-9]` |
| `invalid_quantity` | No es entero entre 1 y 9 999 |
| `invalid_unit_price` | No es decimal con hasta 2 decimales y hasta 7 dígitos enteros (`12,50`, `abc`, `1.234`, `99999999`) |
| `non_positive_unit_price` | Importe ≤ 0 (cero y negativos; un precio cero no es una venta válida) |
| `invalid_transaction_date` | No es una fecha real en formato ISO (`31/02/2025`, `2025-02-30`, `2025-13-45`) |
| `duplicate_transaction_id` | El id (normalizado sin ceros a la izquierda) ya apareció antes en el archivo; **se conserva la primera aparición**, sea válida o no |

- Todos los patrones usan `[0-9]` (no `\d`, que acepta dígitos Unicode).
- Los topes (cantidad ≤ 9 999, precio ≤ 9 999 999.99) garantizan que `total` quepa en `NUMERIC(14,2)`; la BD los repite con `CHECK` (defensa en profundidad).
- Una fila puede tener varios motivos; se guardan como lista (`reasons TEXT[]`).

### 5.2 Qué pasa con los inválidos
1. Se guardan en `rejected_records` (`run_id`, `record_number`, `reasons`, fila original en JSONB).
2. Se escriben en `reports/rejected_<run_id>.csv`, **neutralizando fórmulas**: toda celda que empiece por `=`, `+`, `-`, `@`, tab o retorno se antepone con `'` para que Excel no la ejecute. El JSONB conserva el valor original.
3. **No** se cargan a `sales`.
4. Si superan `MAX_REJECT_RATE` (20 %) → corrida `FAILED`, no se carga nada (los rechazos igual quedan registrados).

### 5.3 Transformaciones (solo filas válidas)
Texto sin espacios sobrantes (colapsados); `category` y `country` con la primera letra de cada palabra en mayúscula usando `string.capwords` (no `str.title`, que rompe apóstrofes: `d'Ivoire` → `D'Ivoire`); tipos `int`, `Decimal`, `date`; `total = quantity × unit_price` exacto. El CSV sintético incluye ~8 % de filas "sucias pero válidas" para que la transformación tenga trabajo visible.

### 5.4 Reportes
| Capa | Qué es | Para qué |
|---|---|---|
| Tablas `etl_runs` y `rejected_records` | Una fila por corrida con estado, conteos, desglose, duración y error; una fila por rechazo | Historial **consultable con SQL**: el argumento DataOps más fuerte |
| Archivos por corrida | `run_<id>.json` y `rejected_<id>.csv` | Evidencia portable; artifact en CI |
| Resumen por stdout | Markdown con los conteos | CI lo anexa a `$GITHUB_STEP_SUMMARY` |

### 5.5 Conciliación (real, contra la BD)
Tres comprobaciones; si alguna falla, la corrida hace rollback y queda `FAILED`:
1. `rows_in = rows_valid + rows_rejected` (aritmética del pipeline; se afirma con un `assert`, no se presenta como control independiente).
2. `rows_valid = rows_loaded + rows_skipped_existing`.
3. **Contra la BD, dentro de la transacción:** `COUNT(*)` en `sales` de los ids del lote igual a `rows_valid`, y `COUNT(*)` con `loaded_by_run = run_id` igual a `rows_loaded`. Esto detecta filas perdidas por un trigger, una restricción o un bug de inserción.

### 5.6 Logging
`structlog` con `run_id` vinculado: consola legible + `logs/etl_<run_id>.jsonl` (`timestamp`, `level`, `run_id`, `event` + campos). Eventos: `run_started`, `extract_done`, `extra_columns`, `validate_done`, `rows_rejected`, `transform_done`, `load_done`, `reconcile_done`, `run_finished`, `run_failed`. **Los logs llevan conteos y códigos, nunca valores de filas** (pueden ser datos personales); los valores crudos solo viven en `rejected_records`. El `run_id` une log, reporte, fila de `etl_runs` y `sales.loaded_by_run`.

---

## 6. Modelo de datos

```sql
-- Idempotent: safe to run on every pipeline start.
CREATE TABLE IF NOT EXISTS etl_runs (
    run_id                TEXT PRIMARY KEY,
    source_file           TEXT        NOT NULL,
    status                TEXT        NOT NULL
        CHECK (status IN ('RUNNING', 'SUCCESS', 'SUCCESS_WITH_REJECTS', 'FAILED')),
    started_at            TIMESTAMPTZ NOT NULL,
    finished_at           TIMESTAMPTZ,
    duration_ms           INTEGER,
    rows_in               INTEGER,
    rows_valid            INTEGER,
    rows_rejected         INTEGER,
    rows_loaded           INTEGER,
    rows_skipped_existing INTEGER,
    rejection_breakdown   JSONB,
    error_message         TEXT
);

CREATE TABLE IF NOT EXISTS sales (
    transaction_id   BIGINT PRIMARY KEY,
    product          TEXT          NOT NULL,
    category         TEXT          NOT NULL,
    quantity         INTEGER       NOT NULL CHECK (quantity BETWEEN 1 AND 9999),
    unit_price       NUMERIC(12,2) NOT NULL CHECK (unit_price > 0 AND unit_price <= 9999999.99),
    total            NUMERIC(14,2) NOT NULL CHECK (total = quantity * unit_price),
    transaction_date DATE          NOT NULL,
    country          TEXT          NOT NULL,
    loaded_by_run    TEXT          NOT NULL REFERENCES etl_runs (run_id)
);

CREATE TABLE IF NOT EXISTS rejected_records (
    id            BIGSERIAL PRIMARY KEY,
    run_id        TEXT    NOT NULL REFERENCES etl_runs (run_id),
    record_number INTEGER NOT NULL,
    reasons       TEXT[]  NOT NULL CHECK (cardinality(reasons) > 0),
    raw           JSONB   NOT NULL
);
```

`sales.loaded_by_run` da el linaje básico. El desglose de rechazos por motivo también se obtiene con `SELECT r, COUNT(*) FROM rejected_records, unnest(reasons) r WHERE run_id = … GROUP BY r`; `rejection_breakdown` es una instantánea de la corrida.

---

## 7. Seguridad

| Área | Decisión |
|---|---|
| SQL | Solo consultas parametrizadas; ninguna cadena SQL se arma con datos del CSV |
| Defensa en profundidad | Las reglas de §5.1 se repiten como `CHECK` en la BD (rangos, `total = quantity * unit_price`, `reasons` no vacío) |
| Secretos | los `.env` se ignoran en git y se versionan los `.env.sample` con valores de demo. Compose exige las variables de PostgreSQL (`${VAR:?…}`); no hay credenciales en `compose.yml`, `Dockerfile` ni código (CI las define en el workflow) |
| Red | La BD se publica solo en `127.0.0.1` (`"127.0.0.1:${DB_PORT:-5432}:5432"`); entre contenedores se usa la red interna |
| Imagen | Base y uv con **versión fija** (no `latest`); usuario **no root**; `.dockerignore` (ver §8; excluye los `.env`); `uv sync --locked` |
| Dependencias | Versiones exactas en `uv.lock` |
| CI | `permissions: contents: read`; actions fijadas por versión (idealmente por SHA); `concurrency` para cancelar corridas viejas |
| Entrada no confiable | Límite de tamaño de archivo; rangos de valores; la ruta de los reportes se forma solo con `run_id` generado, nunca con datos del CSV |
| Salida | CSV de rechazados con neutralización de fórmulas; logs sin valores de filas |
| Tiempo | Todo en UTC (`TIMESTAMPTZ`) |

---

## 8. Estructura del proyecto

Todo el proyecto vive en `project/` (proyecto uv llamado `piper`). En la raíz del repo solo quedan lo que las herramientas exigen allí (`.github/`, `.claude/`) y el `README.md`.

```
poc-pipeline-isw/
├─ README.md                     = §11 de este documento
├─ .github/workflows/ci.yml      Actions solo lee workflows desde la raíz del repo
├─ .claude/
└─ project/
   ├─ compose.yml                compose raíz (name: piper): incluye database y define etl
   ├─ Dockerfile                 imagen del servicio etl (contexto de build: project/)
   ├─ .env.sample                ajustes de la aplicación (se copia a .env, que no se versiona)
   ├─ .gitignore  .dockerignore  .gitattributes  .python-version (3.12)
   ├─ pyproject.toml             nombre piper, dependencias, script, config de pytest y ruff
   ├─ uv.lock                    se commitea
   ├─ docker/
   │  └─ database/
   │     ├─ compose.yml          servicio database (postgres:17-alpine)
   │     └─ .env.sample          credenciales de PostgreSQL (se copia a .env)
   ├─ deltas/                    etl-run.spec.md (se escribe después con specifier)
   ├─ data/                      sales_valid.csv, sales_invalid.csv (sintéticos, reproducibles)
   ├─ source/                    paquete principal `source`, sin __init__.py (namespace package)
   │  ├─ cli  config  logging_setup
   │  ├─ extract  schema (pandera)  validate  transform
   │  └─ load  report  pipeline  generate_data  schema.sql
   └─ testing/
      ├─ conftest  test_validate  test_transform  test_report
      └─ test_generate_data  test_properties  test_pipeline_integration
```

**Paquete y nombres (lo que `uv init` generó queda renombrado):**
- El paquete importable es `source` (los módulos viven directamente en `project/source/`, p. ej. `from source.validate import validate`). No hay subcarpeta `etl/`.
- `pyproject.toml`: `name = "piper"`, script `piper = "source.cli:main"`, se elimina `readme = "README.md"` (no hay README dentro de `project/` y el build fallaría) y se escribe una `description` real. Backend `uv_build` configurado así (**verificado** en un proyecto de prueba: `uv sync`, `uv run piper`, lectura de `schema.sql` con `importlib.resources.files("source")` y wheel con todos los archivos):
  ```toml
  [tool.uv.build-backend]
  module-name = "source"
  module-root = ""
  namespace = true
  ```
- Sin `__init__.py` ni ningún archivo con `__` en el nombre (tampoco `__main__.py`): el punto de entrada es `cli.py` y el comando `piper`. `namespace = true` es lo que permite el paquete sin inicializador con `uv_build`. Ajustes de herramientas: `[tool.pytest.ini_options] testpaths = ["testing"]`; ruff usa su detección por defecto de código propio (la carpeta `source` está en la raíz del proyecto). Los nombres de archivo de pruebas deben ser únicos en `testing/` (pytest sin `__init__` importa por nombre de archivo).
- `source` es un nombre de paquete de nivel superior muy genérico; es aceptable porque el proyecto no se publica, pero habría que renombrarlo si alguna dependencia expusiera un módulo `source`.

**Dependencias:** se declaran solo en `pyproject.toml` y `uv.lock`. **No hay `requirements.txt`** (decisión del proyecto). El enunciado original lo menciona como entregable; esta desviación se comunica a Iván (§16) y el README explica `uv sync --locked`.

Runtime `pandas`, `pandera`, `structlog`, `psycopg[binary]`; dev `pytest`, `hypothesis`, `ruff`. Se agregan con `uv add` desde `project/`.

Principio de módulos: `pipeline.py` solo orquesta y delega en funciones cortas (abrir corrida, leer+validar, cuarentena, umbral, cargar+conciliar, cerrar corrida). El `except` traduce a `FAILED`; el `finally` solo cierra conexión, actualiza `etl_runs` y escribe reportes.

### Configuración (variables de entorno)
Dos archivos `.sample`, cada uno con un dueño, para no repetir credenciales:

| Archivo | Variables | Quién lo lee |
|---|---|---|
| `docker/database/.env` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | Servicio `database` **y** servicio `etl` (vía `env_file`) |
| `.env` | `DB_PORT` (puerto publicado en el host), `MAX_REJECT_RATE`, `MAX_INPUT_MB` | Compose (interpolación) y servicio `etl` |

La aplicación arma la conexión desde `POSTGRES_HOST` (default `localhost`; en Compose vale `database`), `POSTGRES_PORT` (default `5432`; en Compose vale `5432` fijo, es el puerto interno), `POSTGRES_USER`, `POSTGRES_PASSWORD` y `POSTGRES_DB`, pasándolos como parámetros separados a psycopg. Así no hay `DATABASE_URL` y no hace falta codificar caracteres especiales en la clave.

| Variable | Default | Uso |
|---|---|---|
| `REPORTS_DIR` / `LOGS_DIR` | `reports` / `logs` | Salidas |
| `MAX_REJECT_RATE` | `0.2` | Circuit breaker |
| `MAX_INPUT_MB` | `50` | Tamaño máximo del archivo |

### Imagen y Compose (referencia)
`project/Dockerfile` (contexto de build = `project/`):
```dockerfile
FROM python:3.12-slim
COPY --from=ghcr.io/astral-sh/uv:<VERSION_FIJA> /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PATH="/app/.venv/bin:$PATH"
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY source ./source
RUN uv sync --locked --no-dev
RUN useradd --create-home --uid 10001 piper && mkdir -p /app/reports /app/logs && chown piper /app/reports /app/logs
USER piper
ENTRYPOINT ["piper"]
```
`project/docker/database/compose.yml`:
```yaml
services:
  database:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER:?set it in docker/database/.env}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set it in docker/database/.env}
      POSTGRES_DB: ${POSTGRES_DB:?set it in docker/database/.env}
    ports:
      - "127.0.0.1:${DB_PORT:-5432}:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10
volumes:
  pgdata:
```
`project/compose.yml`:
```yaml
name: piper
include:
  - path: docker/database/compose.yml
    env_file:
      - docker/database/.env
      - .env
services:
  etl:
    build:
      context: .
      dockerfile: Dockerfile
    profiles: ["etl"]            # not started by `up`; launched on demand with `run`
    depends_on:
      database:
        condition: service_healthy
    env_file:
      - docker/database/.env
      - .env
    environment:
      POSTGRES_HOST: database
      POSTGRES_PORT: "5432"
      REPORTS_DIR: /app/reports
      LOGS_DIR: /app/logs
    volumes:
      - ./data:/app/data
      - ./reports:/app/reports
      - ./logs:/app/logs
```
**Verificado:** esta composición (con `include` + `env_file`, y con los `.env` presentes) resuelve sin errores con `docker compose --profile etl config` en un directorio de prueba. **No ejecutado:** `up`, `build` ni `run`.

`project/.dockerignore`: `.venv`, `.git`, `.env`, `docker/database/.env`, `reports`, `logs`, `testing`, `deltas`, `docker`, `__pycache__`. Los `.env` quedan fuera de la imagen (las variables llegan por `env_file` en tiempo de ejecución). `reports/` y `logs/` viven en `project/` y están en `.gitignore`, igual que los `.env`.

Si 5432 está ocupado: `DB_PORT=5433` en `.env` (solo cambia el puerto hacia afuera). En Linux, un usuario no root puede no tener permiso de escritura en los directorios montados (riesgo §15).

### Datos sintéticos
Deterministas (semilla fija) con defectos plantados en posiciones fijas: 12 rechazos esperados (3 precios negativos → `non_positive_unit_price`, 2 productos vacíos, 2 ids duplicados, 2 fechas inválidas, 2 cantidades inválidas, 1 precio con coma). El archivo inválido usa ids desde 10 001 para poder cargar primero el válido y luego el inválido en la misma BD (1 000 + 988 = 1 988 filas). Los defectos se declaran como `(índice, columna, valor)` explícitos, sin convenciones cifradas. El generador vive en el paquete (`piper generate-data`) para poder correrlo con `docker compose run`.

### CLI
`piper run <csv>` y `piper generate-data [--out]`. Código de salida `1` si la corrida terminó `FAILED`, `0` en otro caso (así CI se pone rojo).

---

## 9. Pruebas

El número total lo reporta pytest; no se fija aquí. Se cubre:

| Grupo | Tipo | Qué demuestra |
|---|---|---|
| Validación | Unitaria (parametrizada) | Cada regla rechaza con su código exacto; duplicados (gana la primera); varios motivos por fila; **cada borde de §5.1** (topes de cantidad y precio, precio cero, ceros a la izquierda, dígitos no ASCII, BOM, línea en blanco, columnas de más/menos) |
| Transformación | Unitaria | Texto normalizado (`capwords`), tipos y `total` exacto con `Decimal` |
| Reporte | Unitaria | Contenido de JSON/markdown/CSV; neutralización de fórmulas en el CSV; no hay CSV si no hay rechazos |
| Datos sintéticos | Unitaria | Generación determinista; el inválido produce **exactamente** los 12 rechazos planeados con el desglose esperado |
| Propiedades | hypothesis | Para cualquier tabla de entrada: `válidas + rechazadas = entrada`, ninguna fila rechazada llega a la salida, ids únicos en las válidas |
| Integración | PostgreSQL real | Corrida válida; cuarentena sin carga silenciosa; idempotencia; válido + inválido acumulan; umbral → `FAILED` sin carga; columnas faltantes; archivo inexistente o demasiado grande; BD caída aún genera reporte; la conciliación detecta una inconsistencia forzada |

- **`REQUIRE_DB=1`** (lo pone CI): si PostgreSQL no está disponible, las pruebas de integración **fallan** en vez de saltarse, para que una BD caída nunca dé un "verde" falso. Localmente se saltan con aviso.
- Verificación de que las pruebas detectan errores: romper una regla a propósito y ver que fallen. Se documenta lo observado, no se afirma de antemano.
- No se prueba el framework de logging; solo que los eventos esperados lleven `run_id` y que no incluyan valores de filas.

---

## 10. GitHub Actions

```yaml
name: CI
on:
  push:
  pull_request:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: project
    services:
      postgres:
        image: postgres:17-alpine
        env:
          POSTGRES_USER: piper
          POSTGRES_PASSWORD: piper
          POSTGRES_DB: piper
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U piper -d piper"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
    env:
      POSTGRES_HOST: localhost
      POSTGRES_USER: piper
      POSTGRES_PASSWORD: piper
      POSTGRES_DB: piper
      REQUIRE_DB: "1"
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
        with:
          enable-cache: true
      - run: uv sync --locked
      - run: uv run ruff check .
      - run: uv run pytest
      - name: End-to-end run (valid + invalid) and job summary
        run: |
          uv run piper generate-data
          uv run piper run data/sales_valid.csv  | tee -a "$GITHUB_STEP_SUMMARY"
          uv run piper run data/sales_invalid.csv | tee -a "$GITHUB_STEP_SUMMARY"
      - name: Upload reports and logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: etl-reports
          path: |
            project/reports/
            project/logs/
```

- **Service container de PostgreSQL** con healthcheck: integración contra BD real sin compose dentro del runner. Las credenciales `piper/piper` son efímeras del runner y no secretos.
- **`uv sync --locked`**: falla si `pyproject.toml` y `uv.lock` no coinciden.
- **`upload-artifact` con `if: always()`**: reportes y logs descargables aunque algo falle.
- Antes de usarlo, verificar que las versiones de las actions sigan vigentes y fijarlas (idealmente por SHA).
- Captura: push real y ejecución verde. **Opcional y muy visual:** un PR con una regla rota a propósito para capturar el workflow en rojo y luego verde.

---

## 11. Runbook (esto es el README)

**Requisitos:** Docker Desktop, [uv](https://docs.astral.sh/uv/), Git.

```bash
# --- Preparación (todos los comandos, desde project/) ---
cd project
cp .env.sample .env
cp docker/database/.env.sample docker/database/.env   # variables de demo (editar si se desea)

# --- Opción A: todo en Docker (lo que se muestra en la demo) ---
docker compose up -d                                   # solo PostgreSQL (healthy)
docker compose ps
docker compose run --rm etl generate-data              # opcional: los CSV ya vienen en el repo
docker compose run --rm etl run data/sales_valid.csv
docker compose run --rm etl run data/sales_invalid.csv

# Consultas de verificación (usuario/BD según .env)
docker compose exec database psql -U piper -d piper -c "SELECT COUNT(*) FROM sales"
docker compose exec database psql -U piper -d piper -c "SELECT * FROM sales ORDER BY transaction_id LIMIT 5"
docker compose exec database psql -U piper -d piper -c "SELECT run_id, status, rows_in, rows_valid, rows_rejected, rows_loaded, rows_skipped_existing FROM etl_runs ORDER BY started_at"
docker compose exec database psql -U piper -d piper -c "SELECT record_number, reasons FROM rejected_records ORDER BY record_number"

# --- Opción B: desarrollo local con uv (desde project/) ---
uv sync --locked
export POSTGRES_HOST=localhost POSTGRES_USER=piper POSTGRES_PASSWORD=piper POSTGRES_DB=piper   # o los valores de docker/database/.env
uv run ruff check .
uv run pytest -v                                       # necesita la BD arriba (docker compose up -d)
uv run piper run data/sales_valid.csv

# --- Empezar desde cero (borra también los datos de PostgreSQL) ---
docker compose down -v
```

### Guion de la demo
| # | Paso | Qué se muestra |
|---|---|---|
| 1 | Arquitectura (20–30 s) | Diagrama de §4 |
| 2 | Contenedores | `docker compose up -d` + `docker compose ps` (`database` *healthy*) |
| 3 | Corrida válida | `piper run data/sales_valid.csv` → 1000 / 1000 / 0 / 1000, conciliación OK · `SELECT COUNT(*)` y muestra de filas |
| 4 | Dato inválido | `piper run data/sales_invalid.csv` → 988 válidas, 12 rechazadas con desglose · `SELECT … FROM rejected_records` · abrir `rejected_<id>.csv` · `etl_runs` con las dos corridas |
| 5 | Falla controlada (opcional) | `docker compose run --rm -e MAX_REJECT_RATE=0.005 etl run data/sales_invalid.csv` → 1.2 % > 0.5 % ⇒ `FAILED`, nada cargado. *(Por verificar al ejecutarlo.)* |
| 6 | Idempotencia (opcional) | Repetir la corrida válida → `loaded=0, skipped=1000`, el `COUNT(*)` no cambia |
| 7 | Pruebas y CI | `uv run pytest -v` y la pestaña Actions con el workflow verde |
| 8 | Valor DataOps y limitaciones | §13 y §14 |

Respaldo: capturas y/o grabación corta, como pide el enunciado.

---

## 12. Evidencias y tabla de resultados

**Capturas numeradas** (se guardan fuera del repo y se entregan junto con la tabla):

| # | Captura |
|---|---|
| 01 | Contenedores: Docker Desktop y/o `docker compose ps` |
| 02 | Primeras filas de `sales_valid.csv` (y de `sales_invalid.csv` con una fila defectuosa) |
| 03 | Ejecución válida (salida completa con conteos) |
| 04 | `SELECT COUNT(*)` + muestra de filas en PostgreSQL |
| 05 | Ejecución inválida (log con `rows_rejected` y desglose) |
| 06 | `rejected_records`, `rejected_<id>.csv` y `etl_runs` |
| 07 | pytest con el número real de pruebas |
| 08 | Workflow de GitHub Actions (resumen del job + artifacts) |

**Tabla de resultados reales** — se llena con lo que muestre la ejecución real. Los conteos son deterministas, así que *deberían* coincidir con "esperado"; si no, hay un problema que investigar, no un número que ajustar. Los tiempos solo se incluyen si se midieron (`duration_ms`).

| Corrida | Filas iniciales | Aceptadas | Rechazadas | Cargadas | Estado | Esperado |
|---|---:|---:|---:|---:|---|---|
| `sales_valid.csv` (BD vacía) | ___ | ___ | ___ | ___ | ___ | 1000 / 1000 / 0 / 1000 · `SUCCESS` |
| `sales_invalid.csv` (tras la anterior) | ___ | ___ | ___ | ___ | ___ | 1000 / 988 / 12 / 988 · `SUCCESS_WITH_REJECTS` |
| Total en `sales` | | | | ___ | | 1988 |
| pytest | pruebas: ___ | pasadas: ___ | falladas: ___ | | | todas pasadas |
| GitHub Actions | | | | | ___ | verde |

Desglose esperado de los 12 rechazos: `non_positive_unit_price` 3 · `missing_product` 2 · `duplicate_transaction_id` 2 · `invalid_transaction_date` 2 · `invalid_quantity` 2 · `invalid_unit_price` 1.

---

## 13. Explicación breve (para el informe, 1–2 párrafos en español)

> El pipeline lee un CSV de 1 000 ventas sintéticas, lo valida contra reglas declaradas como esquema (campos obligatorios, tipos, rangos, importes positivos, fechas reales y ids únicos), transforma las filas válidas (normalización de texto, tipos y total exacto) y las carga en PostgreSQL de forma idempotente. Las filas inválidas no se cargan ni se descartan: se aíslan en una tabla de cuarentena y en un CSV con los motivos de cada rechazo. Cada corrida queda auditada en la tabla `etl_runs`, con un `run_id` que también aparece en los logs en formato JSON y en los reportes, y el propio pipeline verifica contra la base de datos que los conteos concilien antes de dar la corrida por exitosa.
>
> Las prácticas DataOps se aplicaron así: el entorno (PostgreSQL y el ETL) se levanta con Docker Compose y las dependencias quedan fijadas con `uv.lock`; las pruebas automatizadas con pytest (incluidas pruebas de propiedades) cubren las reglas, las transformaciones y el flujo completo contra una base real; el código está versionado en Git; y GitHub Actions ejecuta lint, pruebas y una corrida completa del pipeline en cada push o pull request. Frente a ejecutar un script a mano, esto da reproducibilidad, detección temprana de regresiones y trazabilidad de qué se cargó, cuándo y qué se rechazó.

(Ajustar cifras y estados a lo realmente medido antes de entregar.)

---

## 14. Limitaciones y pasos manuales (documentarlas, no esconderlas)

- Dataset **sintético** y pequeño (1 000 filas): no representa volumen real. La carga fila por fila no escalaría; habría que usar `COPY`/staging.
- La demo corre en **una máquina**, sin orquestador (Airflow, Dagster, cron…): cada corrida se lanza a mano. Es un **paso manual no automatizado**.
- CI ejecuta el pipeline y las pruebas, pero **no hay despliegue (CD)** ni publicación de la imagen Docker.
- Reportes y logs viven en archivos locales / artifacts de CI; no hay alertas ni dashboard.
- Reglas de calidad fijas en código: sin catálogo configurable ni perfilado estadístico (outliers, rangos por producto). Los topes de cantidad y precio son arbitrarios para este dominio sintético.
- Solo se acepta fecha ISO; `dd/mm/yyyy` se rechaza por ambigüedad (decisión deliberada). No hay regla de fechas futuras.
- **Idempotencia por id, no por contenido:** un id existente con valores distintos se omite (se cuenta como `skipped`) sin comparar los datos.
- **Duplicados:** gana la primera aparición aunque sea inválida; un segundo registro válido con ese id se rechaza.
- `record_number` no coincide con la línea física del archivo si hay campos multilínea entre comillas.
- El usuario de la aplicación crea el esquema (DDL) al arrancar; en un entorno real habría migraciones y un rol de aplicación sin DDL.
- Credenciales de demo solo para entorno local; en un entorno real irían en un gestor de secretos.
- **No verificado aún:** build del `Dockerfile`, `docker compose run`, ejecución del workflow, `on_bad_lines` con función, y el comportamiento con las versiones exactas del lock.

---

## 15. Riesgos y checklist

| Riesgo | Mitigación |
|---|---|
| Puerto 5432 ocupado | `DB_PORT=5433 docker compose up -d` |
| `docker compose run` corre antes de que la BD esté lista | Healthcheck + `depends_on: service_healthy` |
| El workflow falla por algo del runner | Capturas de respaldo; si no se logra, **declararlo como limitación** |
| Sin internet en la sala | Imágenes y dependencias descargadas antes (`docker compose build`, `docker pull`) |
| "Los datos inválidos ya existían en la BD" (idempotencia confunde la demo) | Ejecutar siempre válido → inválido (rangos de ids distintos); para repetir, `docker compose down -v` |
| Diferencias entre versiones locales y CI | `uv sync --locked` en ambos |
| pandas 3 cambia comportamiento respecto a 2.x | Rango fijado en el lock; la suite corre con esa versión desde el primer día |
| Usuario no root sin permiso de escritura en volúmenes montados (Linux) | Probar en la máquina de Iván/Ian; si falla, ajustar `uid` o permisos de `reports/` y `logs/` |
| Fallo en la conversión de fallos de pandera a motivos por fila | Prototipo ya validó el mapeo; si se complica en la implementación, volver a máscaras de pandas |

Checklist:
- [ ] Crear repo en GitHub y primer push
- [ ] `uv lock` y commit de `uv.lock`
- [ ] `docker compose up -d` desde cero funciona
- [ ] `docker compose run --rm etl …` (válido e inválido) y verificar la tabla de §12
- [ ] `uv run pytest` en local y en CI
- [ ] Workflow verde en GitHub Actions + captura
- [ ] Capturas 01–08
- [ ] Probar el README desde cero en otra máquina (Iván o Ian)
- [ ] Compartir con Iván e Ian: stack (con versiones) + reglas (§5) **antes de implementar**; resultados reales y capturas **al terminar**
- [ ] Fijar versiones (uv en el Dockerfile, actions)

---

## 16. Coordinación con Iván e Ian

1. **Ahora, antes de implementar:** avisar que no se entregará `requirements.txt` (las dependencias quedan en `pyproject.toml` y `uv.lock`, que el enunciado cubre con el mismo fin) y compartirles el stack (con versiones: Python, pandas, pandera, structlog, psycopg, PostgreSQL 17, uv) y las reglas de validación de §5.
2. **Al terminar:** diagrama real, comandos, capturas numeradas, tabla de resultados reales, explicación de §13, limitaciones y problemas encontrados (incluidos pasos manuales).
3. No completar la sección experimental con estimaciones; la investigación de fuentes académicas se hace después, cuando Iván lo indique.

---

## 17. Preguntas abiertas

1. ¿Python 3.12 en Docker/CI está bien, o el profe pide otra versión?
2. ¿Repo público (workflow fácil de mostrar) o privado?
3. La "prueba fallida controlada" del enunciado: ¿se muestra con `MAX_REJECT_RATE` (paso 5 del guion) o con una prueba fallida de pytest? Basta una de las dos.
4. ¿Se quiere `pytest-cov` y `pre-commit` más adelante? (fuera de alcance por ahora)

---

## 18. Siguiente paso (flujo de deltas)

- Un solo slice: **`etl-run`** (validar → cuarentena → cargar → conciliar → auditar). Reglas, umbral, idempotencia y conciliación cambian juntos. Se especifica con `specifier` y se escribe con `archivist` en `project/deltas/etl-run.spec.md`.
- Hechos de infraestructura (stack, compose, CI, esquema SQL) y conceptos van a `.claude/docs/` (`structure`, `database`, `expertise`), no a un slice.
- Convenciones vigentes: `commit-conventions`, `lang-english-only` (`project/**/*.py`), `when-write-delta`, `kb-deltas-routing`.
