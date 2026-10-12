# Piper | Pipeline ISW

Pipeline ETL que lee CSV de ventas, valida cada fila contra reglas de calidad, aparta las filas inválidas junto con sus motivos y carga las válidas en PostgreSQL de forma idempotente. Cada corrida queda auditada y se reconcilia contra el estado real de la base de datos, así que ninguna fila se pierde ni se carga en silencio.

**Stack:** Python 3.12 · uv · pandas · pandera · psycopg · structlog · PostgreSQL 17 · Docker Compose · GitHub Actions

---

## Cómo funciona

```
CSV ──► extraer ──► validar ──► transformar ──► cargar ──► reconciliar ──► reportes
        (texto)     │ válidas                   (PostgreSQL)   │
                    │                                          └─ si no cuadra: rollback y FAILED
                    └ inválidas ──► cuarentena (tabla + CSV)
```

1. **Extraer:** el CSV se lee completo como texto, sin convertir nada antes de validar. Un archivo mayor a `MAX_INPUT_MB` se rechaza sin leerse.
2. **Validar:** cada fila pasa por reglas nombradas. Una fila puede violar varias y acumula todos los códigos de motivo.
3. **Umbral:** si la proporción de filas rechazadas supera `MAX_REJECT_RATE`, la corrida falla **antes de cargar nada**. Se asume que el archivo de origen está roto.
4. **Transformar:** precios y totales con aritmética decimal exacta (nunca `float`) y capitalización de textos.
5. **Cargar:** `INSERT ... ON CONFLICT DO NOTHING` por `transaction_id`. Volver a correr el mismo archivo no inserta nada nuevo.
6. **Reconciliar:** se compara lo que la corrida reporta con lo que existe en la base. Si no coincide, se hace rollback de toda la carga y la corrida termina `FAILED`.

Toda fila de entrada termina en un solo lugar: la tabla `sales` o la cuarentena.

### Estados de una corrida

| Estado | Significado | Código de salida |
|---|---|---|
| `SUCCESS` | Todas las filas eran válidas y se reconciliaron | `0` |
| `SUCCESS_WITH_REJECTS` | Hubo rechazos dentro del umbral; las válidas se cargaron | `0` |
| `FAILED` | Umbral superado, columnas faltantes, archivo inexistente, base caída o reconciliación fallida | `1` |
| `RUNNING` | Solo se ve si el proceso murió a mitad de corrida; la fila se inserta primero para dejar rastro | n/a |

### Códigos de rechazo

`missing_product`, `invalid_quantity`, `invalid_unit_price`, `non_positive_unit_price`, `invalid_transaction_date`, `duplicate_transaction_id` (gana la primera aparición) y `wrong_column_count`, entre otros definidos en `project/source/ingest/rules.py`.

---

## Estructura

| Ruta | Contenido |
|---|---|
| `project/` | Toda la aplicación; los comandos se ejecutan desde aquí |
| `project/source/` | Paquete `source`: `config`, `ingest`, `storage`, `output`, `engine`, `tools` y el módulo `cli` |
| `project/testing/` | Pruebas, una carpeta por paquete |
| `project/data/` | CSV sintéticos: `sales_valid.csv` y `sales_defective.csv` |
| `project/docker/database/` | Servicio de PostgreSQL para Compose |
| `project/Dockerfile` | Imagen del pipeline (multi-stage, uv fijado, usuario no root) |
| `project/compose.yml` | Compose raíz: incluye la base de datos y define `piper-etl` |
| `.github/workflows/ci.yml` | CI: lint, pruebas con base real y corrida end to end |

---

## Puesta en marcha

Requisitos: [uv](https://docs.astral.sh/uv/) y Docker con Compose. Todos los comandos se ejecutan desde `project/`.

### 1. Archivos de entorno

Cada `.env` real está ignorado por git; solo se versionan los `.sample`.

```bash
cp .env.sample .env
cp docker/database/.env.sample docker/database/.env
```

| Archivo | Variables |
|---|---|
| `docker/database/.env` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `DB_PORT` (puerto publicado en el host; cámbialo si el 5432 está ocupado) |
| `.env` | `MAX_REJECT_RATE` (default `0.2`; una corrida falla si el rechazo es **estrictamente mayor**), `MAX_INPUT_MB` (default `50`) |

Los valores de los `.sample` son de demostración. Cámbialos si la base va a ser accesible desde fuera de tu máquina.

### 2. Levantar la base de datos

```bash
docker compose up -d --wait
```

`--wait` espera al healthcheck. El esquema se crea solo, con `IF NOT EXISTS`, cada vez que el pipeline arranca.

---

## Ejecutar el pipeline

### Opción A: en contenedor (Compose)

El servicio `piper-etl` pertenece al perfil `etl`, así que `up` no lo arranca; se lanza a demanda con `run`. Espera a que la base esté sana y construye la imagen la primera vez.

```bash
docker compose run --rm piper-etl run data/sales_valid.csv
docker compose run --rm piper-etl run data/sales_defective.csv
```

Todo lo que va después de `piper-etl` son argumentos del comando `piper`. Para regenerar los datasets:

```bash
docker compose run --rm piper-etl generate --output data
```

Compose monta `./data`, `./reports` y `./logs` dentro del contenedor, así que los resultados aparecen en tu carpeta. En Linux, el usuario del contenedor (uid 10001) puede no tener permiso de escritura en `reports/` y `logs/`; ajusta los permisos de esas carpetas si ocurre.

### Opción B: en local con uv

```bash
uv sync
uv run --env-file .env --env-file docker/database/.env piper run data/sales_valid.csv
```

Localmente `POSTGRES_HOST` vale `127.0.0.1` por defecto y se conecta al puerto publicado `DB_PORT`.

---

## Qué esperar de los datasets

Son deterministas: siempre producen los mismos números.

| Archivo | Filas | Válidas | Rechazadas | Estado |
|---|---|---|---|---|
| `sales_valid.csv` | 1000 | 1000 | 0 | `SUCCESS` |
| `sales_defective.csv` | 1000 | 988 | 12 | `SUCCESS_WITH_REJECTS` |

Los 12 rechazos del archivo defectuoso son 3 precios negativos, 2 productos vacíos, 2 identificadores duplicados, 2 fechas inválidas, 2 cantidades inválidas y 1 precio con coma decimal. Sus identificadores empiezan en 10001, de modo que puedes cargar primero el válido y después el defectuoso en la misma base (1000 + 988 = 1988 filas en `sales`).

Una segunda corrida del mismo archivo reporta `Rows loaded 0` y `Rows skipped (already existing) 1000`: esa es la idempotencia en acción. Idempotencia es **por identificador**; si un `transaction_id` ya existe con otros valores, la fila se omite, no se actualiza.

---

## Dónde ver los resultados

### Por consola

Cada corrida imprime los eventos estructurados (`run_started`, `validate_done`, `load_done`, `reconcile_done`, `run_finished`) y un resumen en Markdown con los conteos y el desglose de rechazos.

### En `reports/` y `logs/`

| Archivo | Contenido |
|---|---|
| `reports/<run_id>.json` | Reporte de la corrida con todos los conteos |
| `reports/<run_id>_rejected.csv` | Filas rechazadas con su número de registro, motivos y valores originales (solo si hubo rechazos) |
| `logs/<run_id>.jsonl` | Eventos de la corrida, uno por línea |

El `run_id` tiene la forma `AAAAMMDDTHHMMSS-xxxxxx` y une el log, el reporte, la fila de auditoría y las ventas cargadas. Los logs y reportes llevan solo conteos y códigos, nunca valores de las filas. Los valores originales viven únicamente en `rejected_records` y en el CSV de cuarentena. Ese CSV neutraliza fórmulas: un valor como `-5.00` aparece como `'-5.00` para que Excel no lo interprete.

### En la base de datos

```bash
docker compose exec piper-database sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

| Tabla | Contiene |
|---|---|
| `etl_runs` | Una fila de auditoría por corrida: estado, conteos, duración, error |
| `sales` | Ventas válidas; `loaded_by_run` indica qué corrida las cargó |
| `rejected_records` | Cuarentena: una fila por registro rechazado, con todos sus motivos y valores originales |

```sql
-- Últimas corridas
SELECT run_id, status, rows_in, rows_loaded, rows_rejected, rows_skipped_existing
FROM etl_runs ORDER BY started_at DESC LIMIT 5;

-- Rechazos por motivo
SELECT r, COUNT(*) FROM rejected_records, unnest(reasons) r GROUP BY r ORDER BY r;

-- Ventas cargadas por una corrida
SELECT COUNT(*) FROM sales WHERE loaded_by_run = '<run_id>';
```

La base también aplica las reglas con restricciones `CHECK` (rango de cantidad, precio positivo, `total = cantidad × precio`), así que un error en el código no puede guardar un valor fuera de rango.

---

## Pruebas y lint

La base debe estar levantada: las pruebas de integración corren contra PostgreSQL real y fallan si no la encuentran.

```bash
uv run ruff check .
uv run --env-file .env --env-file docker/database/.env pytest
```

La suite incluye una prueba de propiedades (hypothesis) que verifica que `válidas + rechazadas = entrada` para cualquier entrada.

---

## Reiniciar desde cero

```bash
docker compose down -v
```

Borra el contenedor y el volumen con los datos. Útil para repetir una demostración desde una base vacía.

---

## Integración continua

El workflow `.github/workflows/ci.yml` corre en cada push y pull request:

1. Levanta un PostgreSQL 17 como service container con healthcheck.
2. `uv sync --locked`: falla si `pyproject.toml` y `uv.lock` no coinciden.
3. `ruff check` y `pytest` contra la base real.
4. Corre el pipeline sobre ambos datasets y añade el resumen Markdown al *job summary*.
5. Sube `reports/` y `logs/` como artifact, incluso si algo falla.

Las credenciales del workflow son valores desechables para un contenedor efímero. Las actions están fijadas por SHA.

---

## Solución de problemas

| Síntoma | Causa probable |
|---|---|
| `missing required environment variable POSTGRES_USER` | Falta pasar los `.env`; en local usa `--env-file .env --env-file docker/database/.env` |
| El puerto 5432 está ocupado al hacer `up` | Cambia `DB_PORT` en `docker/database/.env` |
| Una corrida termina `FAILED` por umbral | El rechazo superó `MAX_REJECT_RATE`; no se cargó nada, pero la cuarentena queda guardada |
| Error de conexión en local | La base no está arriba: `docker compose up -d --wait` |
| Error de permisos en `reports/` o `logs/` (Linux) | El contenedor corre con uid 10001; ajusta los permisos de esas carpetas |

---

## Límites conocidos

- No es una plataforma de datos de producción: no hay scheduler, despliegue, publicación de imagen ni alertas. Cada corrida se lanza a mano.
- La carga es fila por fila a propósito, porque el conteo por sentencia es lo que permite distinguir filas nuevas de existentes. A mayor volumen se cambiaría por una carga masiva a una tabla de paso.
- No hay migraciones de esquema; la base es desechable.
- Solo se aceptan fechas ISO (`AAAA-MM-DD`); no se adivinan formatos.
- Un único rol de base de datos hace DDL y DML. En un despliegue real se separarían.
