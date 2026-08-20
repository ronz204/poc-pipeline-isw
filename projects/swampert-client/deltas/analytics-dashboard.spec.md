# Dashboard de Análisis — Spec

## Objetivo

Dar a `projects/swampert-client` un dashboard de solo lectura, protegido por login, que muestra en 3 pantallas navegables (KPIs, Tendencias, Análisis detallado) los datos ya calculados en `reports.monthly_execution_summary`, `reports.swarm_task_summary` y `reports.error_summary`, con un filtro de rango de fechas que efectivamente cambia lo mostrado y un botón que dispara `POST /api/reports/refresh` — sin recalcular ningún agregado en el cliente a partir de datos crudos, y sin volver a consultar la base de datos en cada cambio de filtro. Satisface `approach.md` §6 (Dashboard de análisis, 15 pts).

## Alcance

**Incluido en esta pasada:**

- Login real: un formulario que llama `POST /api/auth/login` contra el backend ya construido (`tenantSlug`, `email`, `password`), guarda el JWT devuelto y lo adjunta como `Authorization: Bearer <token>` en cada llamada subsiguiente. Es el mismo flujo que se demuestra en vivo en la revisión oral (`approach.md` §8).
- 3 pantallas, navegables por pestañas, cada una con su propia ruta bajo `/dashboard`:
  - **KPIs** — tarjetas con números grandes (ejecuciones totales, duración promedio, costo total del rango seleccionado) más el botón "Actualizar reportes".
  - **Tendencias** — gráfico de línea con la evolución de `monthly_execution_summary` a lo largo de los últimos 12 meses.
  - **Análisis detallado** — dos secciones: desglose de tareas por swarm/estado (`swarm_task_summary`) y desglose de errores por severidad (`error_summary`).
- Filtro de rango de fechas, funcional: aplica a KPIs y Tendencias (ambas alimentadas por tablas con columna `period`) y a la sección de errores de Análisis detallado (`error_summary` también tiene `period`). **No aplica** a la sección de tareas por swarm (`swarm_task_summary` no tiene dimensión temporal — ver Riesgos).
- Botón "Actualizar reportes" en la pantalla de KPIs: llama `POST /api/reports/refresh` con el período correspondiente al mes actual del rango seleccionado, y vuelve a pedir los datos al terminar. Cubre `approach.md` §8.5 ("correr el procedimiento de resumen y mostrar las tablas de consolidados actualizadas") dentro del propio dashboard.
- Sesión de usuario (token, `tenantId`, `userId`, `role`) en un store de Pinia — ver **Contexto técnico** para la justificación de por qué esto es la única pieza de estado que sale de las composables.
- Nuevas variables de entorno del lado del cliente: `VITE_API_BASE_URL`.

**Explícitamente fuera de alcance, y por qué es seguro dejarlo afuera:**

- **RBAC/restricción de UI por rol.** El backend todavía no aplica `role` (`admin`/`member`/`viewer`) por ruta (`deltas/restful.spec.md` § Riesgos, punto 3) — el dashboard tampoco lo hace: cualquier usuario autenticado ve exactamente el mismo dashboard. Revisar solo si el backend empieza a exigirlo.
- **La pantalla de historial de auditoría** (`GET /api/audit/:table/history`). Es un ítem de demo separado de la revisión oral (`approach.md` §8.4), no parte del dashboard que pide §6 (que enumera explícitamente KPIs/Tendencias/Análisis detallado, nada de auditoría).
- **Backfill histórico o refrescar más de un período por click.** El botón de refresh dispara un único período por llamada, igual que el propio procedimiento (`reports.sp_refresh_reports` recalcula un mes por `CALL` — `deltas/reports.spec.md` § Alcance). Encadenar 12 llamadas para poblar un año es un caso de uso de seeding, no de este dashboard.
- **Cambios de infraestructura del lado del engine** (roles de Postgres, grants, el valor real de `CORS_ORIGIN`). Este spec solo documenta que el origen del cliente debe estar en `CORS_ORIGIN` del engine para que el dev server funcione — no lo implementa ni lo verifica, porque `.env*` no es legible por política del repo.
- **Paginación** en cualquiera de las lecturas de `reports/*`. El volumen actual (≤12 meses, un puñado de swarms por tenant) no la necesita; reconsiderar solo si eso deja de ser cierto.

## Contexto técnico

**Estado actual del cliente** (verificado leyendo el código, no asumido): `projects/swampert-client/source` tiene únicamente `App.vue` ("hello world from swampert"), `style.css`, `router.ts` (rutas vacías) y `main.ts`. No existe autenticación, ni llamadas HTTP, ni ningún componente de dashboard — esta pasada es greenfield del lado del cliente, consumiendo un backend ya terminado.

**Contrato del backend que este dashboard consume** (verificado contra el código real del engine, no contra la documentación):

| Endpoint | Requiere JWT | Notas |
|---|---|---|
| `POST /api/auth/login` | no | body `{tenantSlug, email, password}` → `200 {token, tenantId, userId, role}` o `401 {error}`. `email` es único solo dentro de un tenant (`unique(tenantId, email)` en `auth.users`), por eso `tenantSlug` es obligatorio — la respuesta ya trae `tenantId`/`userId`/`role` resueltos, el cliente nunca necesita decodificar el JWT. |
| `GET /api/reports/monthly-executions?period=<date>` | sí | `period` es opcional y de **igualdad exacta** — no existe un parámetro de rango en el backend. Omitirlo devuelve **todos** los meses que ese tenant tiene (hasta 12, sembrados por `ReportsSeeder.seedHistory()`). Cada fila: `{tenantId, period, executionCount, avgDurationSeconds: string\|null, totalCost, refreshedAt}`. |
| `GET /api/reports/swarm-tasks?swarmId=<uuid>` | sí | Sin dimensión de fecha — snapshot del estado actual (`{tenantId, swarmId, taskStatus, taskCount, refreshedAt}`). Re-ejecutar el refresh para un período pasado igual sobrescribe esta tabla con los conteos de estado de **hoy** (`deltas/reports.spec.md` § Riesgos, punto 4) — el filtro de rango de fechas no puede aplicarse acá. |
| `GET /api/reports/errors?period=<date>` | sí | Misma semántica de igualdad exacta que `monthly-executions`. Cada fila: `{tenantId, period, severity, errorCount, refreshedAt}`. |
| `POST /api/reports/refresh` | sí | body `{period: Date}` → `{status: "accepted"}`. Es `reports.sp_refresh_reports`: recalcula un único mes, para **todos** los tenants, en un loop del lado del servidor — no solo el tenant que llama. |

Toda ruta salvo `/api/auth/login` exige `Authorization: Bearer <token>` (`AuthGuardPlugin`, `source/feats/shared/auth.guard.plugin.ts` en el engine) — un token ausente o inválido corta con `401` antes de tocar la base de datos.

**Reconciliación: filtro de rango de fechas vs. "sin cálculo en el momento de la consulta".** `approach.md` §6 prohíbe que el dashboard calcule agregados al momento de consultar, precisamente para poder cumplir el presupuesto de respuesta (< 1 segundo). El backend, sin embargo, no expone un parámetro de rango real — solo igualdad exacta por `period` o "todos los meses". La solución de este spec: el cliente pide **una sola vez por carga de pantalla** el arreglo completo sin filtrar (como mucho 12 filas para `monthly-executions`/`errors`), y una composable local (`useDateRangeFilter`) recorta ese arreglo ya agregado según el rango elegido, puramente en el cliente. Esto es filtrar filas que ya vienen agregadas, no recalcular un agregado desde datos operacionales — no vuelve a golpear la base de datos en cada cambio de filtro y nunca toca `core.*`/`trace.*` directamente, por lo que se mantiene dentro de la restricción de §6. Las tarjetas de KPI que suman/promedian esas mismas filas ya agregadas (ej. sumar `executionCount` de los meses visibles) son la misma categoría de aritmética del lado del cliente sobre valores pre-agregados — ver **Riesgos** para por qué esto es una interpretación deliberada, no un hecho obvio.

**`avgDurationSeconds` puede ser `null`.** Un mes con ejecuciones pero ninguna aún terminada no tiene promedio que reportar — la UI debe mostrar explícitamente algo como "sin datos aún", nunca forzarlo a `0` (regla ya establecida en `deltas/reports.spec.md` § Riesgos, punto 3, que este dashboard hereda tal cual).

**Configuración de red para desarrollo local.** El engine escucha en `APP_PORT` (default `3000`, `source/cmd/secrets.ts`) bajo el prefijo `/api` — la URL base local es `http://localhost:3000/api`. El `OriginsPlugin` del engine (`source/infra/plugins/origins.plugin.ts`) valida contra `env.CORS_ORIGIN`, una lista obligatoria sin default — el origen del dev server de Vite (`http://localhost:5173` por defecto) tiene que estar en el `CORS_ORIGIN` del `.env.local` del engine, o las llamadas del dashboard fallarán por CORS antes de llegar al backend. Este spec deja esto documentado como dependencia, no lo verifica (`.env*` no es legible por la política de este repo).

**Pinia — conflicto detectado y resuelto con el usuario, no silenciado.** `package.json` de `swampert-client` ya tiene `"pinia": "^4.0.3"` agregado como dependencia sin commitear (confirmado con `git diff`), lo cual contradice el texto actual de `.claude/rules/client.md`: *"nothing beyond Vue's own reactivity is installed yet... deliberate for the project's current size, not an oversight to fix preemptively"*. Resolución explícita del usuario para este spec: Pinia se usa **únicamente** para el estado de sesión (`token`, `tenantId`, `userId`, `role`) — es exactamente el caso que la propia regla describe como el punto en el que composables dejan de alcanzar: estado necesario en partes no relacionadas del árbol (el guard de rutas, cada llamada HTTP) sin una relación padre/hijo natural. El filtro de rango de fechas del dashboard **no** va a Pinia — sigue siendo una composable local, el default de `client.md` se mantiene para todo lo demás. **Pendiente, fuera de este spec:** `.claude/rules/client.md` sigue afirmando que no hay librería de estado instalada — ese texto queda desactualizado por esta decisión y necesita una edición de seguimiento (no se edita en esta pasada; se deja señalado acá para que el usuario decida cuándo).

**Chart.js sin wrapper.** `chart.js@^4.5.1` ya es una dependencia; no se agrega `vue-chartjs`. Una composable propia (`useChart`) crea y destruye la instancia de `Chart` sobre un `ref` de `<canvas>` a mano, siguiendo el ciclo de vida de Vue (`onMounted`/`onUnmounted`, `watch` sobre los datos para `chart.update()`).

**Convenciones del cliente a seguir** (`.claude/rules/client.md`, no re-derivadas acá, solo aplicadas): Composition API únicamente; clases para código de tipo servicio (los clientes HTTP), composables para todo lo reactivo; `erasableSyntaxOnly` activo en `tsconfig.app.json` — nada de parameter properties en constructores ni `enum` (los campos de una clase se declaran explícitos y se asignan en el constructor; un estado cerrado como `taskStatus`/`severity` se modela como union de string literals, no `enum`); alias de path declarados en `tsconfig.app.json` **y** `vite.config.ts` a la vez (`@assets/*`, `@shared/*`, `@designs/*`, `@features/*` ya existen — no se necesita un alias nuevo, `source/features/*` y `source/shared/*` ya están cubiertos); modo estricto activo (`noUnusedLocals`, `noUnusedParameters`, `noFallthroughCasesInSwitch`).

## Implementación

Plan de implementación (todavía no construido — orden sugerido, no pseudocódigo):

1. **`.env.sample` / `.env.local`**: agregar `VITE_APP_API_BASE_URL` — rebautizado con prefijo `VITE_` obligatorio para que Vite lo exponga (`VITE_API_BASE_URL`), default de desarrollo `http://localhost:3000/api`.

2. **`source/features/auth/`**
   - `auth.client.ts` — clase `AuthApiClient`, un método `login(tenantSlug, email, password)` que hace `POST /api/auth/login` y devuelve `{token, tenantId, userId, role}` o lanza en `401`.
   - `auth.store.ts` — `defineStore("auth", ...)` de Pinia: estado `token`, `tenantId`, `userId`, `role` (unión de literales `"admin" | "member" | "viewer"`, no `enum`); acciones `login()` (delega en `AuthApiClient`) y `logout()`; persistencia en `localStorage` para sobrevivir un refresh de página.
   - `LoginView.vue` — formulario `tenantSlug`/`email`/`password`, llama a la acción `login()` del store, redirige a `/dashboard/kpis` en éxito, muestra el mensaje uniforme de `401` en error.

3. **`source/features/reports/`**
   - `reports.client.ts` — clase `ReportsApiClient` con un método por endpoint (`monthlyExecutions`, `swarmTasks`, `errors`, `refresh`), toma el token del store de auth y lo adjunta como `Authorization: Bearer <token>` en cada llamada.
   - `useDateRangeFilter.ts` — composable local (no Pinia): `ref<[Date, Date] | null>` para el rango elegido, `computed` que recorta un arreglo de filas ya agregadas por su columna `period`.
   - `KpisView.vue` — pide `monthlyExecutions()` sin filtro de servidor, aplica `useDateRangeFilter` en el cliente, muestra tarjetas (ejecuciones totales, duración promedio, costo total del rango) y el botón "Actualizar reportes".
   - `TrendsView.vue` — mismos datos que KPIs, mismo filtro de rango, renderizados como gráfico de línea vía `useChart`.
   - `DetailView.vue` — dos secciones: tabla/gráfico de barras de `swarmTasks()` (sin filtro de fecha, ver **Riesgos**) y tabla/gráfico de barras de `errors()` (con el mismo `useDateRangeFilter`).
   - `components/KpiCard.vue`, `components/RefreshButton.vue`, `components/TrendChart.vue`, `components/SwarmTaskBreakdown.vue`, `components/ErrorSeverityBreakdown.vue` — piezas de presentación, sin llamadas HTTP propias, reciben datos ya resueltos por vía de props.

4. **`source/shared/`**
   - `DashboardLayout.vue` — shell con navegación por pestañas (`<RouterLink>`) envolviendo las 3 vistas de dashboard.
   - `useChart.ts` — composable que crea una instancia `Chart` sobre un `ref<HTMLCanvasElement>` en `onMounted`, la destruye en `onUnmounted`, y la actualiza (`chart.update()`) en un `watch` sobre los datos de entrada.

5. **`source/router.ts`** — reemplaza el arreglo vacío de rutas:
   - `/login` → `LoginView.vue`, pública.
   - `/dashboard` → `DashboardLayout.vue`, con hijos `kpis` (default/redirect), `trends`, `detail` → `KpisView.vue`/`TrendsView.vue`/`DetailView.vue`.
   - `router.beforeEach` consulta el store de auth; si no hay `token`, redirige a `/login`; si lo hay y la ruta es `/login`, redirige a `/dashboard/kpis`.

6. **`main.ts`** — agrega `app.use(createPinia())` antes de `app.use(router)`.

## Configuración / secretos

- `VITE_API_BASE_URL` (nuevo, `.env.sample`/`.env.local` del cliente) — URL base del engine incluyendo `/api`. Default de desarrollo: `http://localhost:3000/api`.
- Dependencia de `CORS_ORIGIN` del **engine** (no de este proyecto): debe incluir el origen del dev server del cliente (`http://localhost:5173` por defecto de Vite) para que las llamadas no fallen por CORS. Documentado acá porque este spec depende de ese valor, no porque lo administre.
- No se necesita ningún secreto nuevo del lado del cliente — el JWT lo emite y valida el engine; el cliente solo lo guarda y lo reenvía.

## Criterios de aceptación

- [ ] Existe una pantalla de login que llama `POST /api/auth/login` con datos de un usuario sembrado activo y guarda el token recibido — `approach.md` §8 (demo en vivo del acceso).
- [ ] Un intento de acceder a `/dashboard/*` sin sesión redirige a `/login`; con sesión, `/login` redirige a `/dashboard/kpis` — el guard de rutas realmente protege las 3 pantallas.
- [ ] Existen exactamente 3 pantallas navegables por pestañas: KPIs, Tendencias, Análisis detallado — `approach.md` §6.
- [ ] La pantalla de KPIs muestra tarjetas con números grandes (ejecuciones totales, duración promedio, costo total) calculados sobre filas ya agregadas del rango seleccionado, sin volver a pedir datos al servidor por cada cambio de filtro.
- [ ] La pantalla de Tendencias muestra un gráfico de línea con la evolución de `monthly_execution_summary` a lo largo de hasta 12 meses.
- [ ] La pantalla de Análisis detallado muestra dos desgloses: tareas por swarm/estado (`swarm_task_summary`) y errores por severidad (`error_summary`), como tabla o gráfico de barras.
- [ ] El filtro de rango de fechas existe, es funcional (cambia realmente lo mostrado en KPIs, Tendencias, y la sección de errores de Análisis detallado) y no dispara una nueva consulta al servidor por cada cambio — `approach.md` §6 (filtro funcional, no decorativo).
- [ ] El botón "Actualizar reportes" llama `POST /api/reports/refresh` con el período correspondiente y refresca lo mostrado al recibir `{status: "accepted"}` — cubre `approach.md` §8.5 dentro del propio dashboard.
- [ ] Un valor `avgDurationSeconds: null` se muestra como "sin datos aún" (o equivalente), nunca como `0`.
- [ ] `swarm_task_summary` se muestra sin intentar aplicarle el filtro de rango de fechas (no tiene columna `period`) — no hay un control de fecha que aparente afectar esta sección sin hacerlo realmente.
- [ ] `main.ts` registra Pinia; el store de auth es el único store de Pinia de este dashboard — el filtro de fechas sigue siendo una composable local.

## Cómo probar

1. `bun run dev` en `projects/swampert-client` con el engine corriendo (`bun run source/cmd/service.ts` en `projects/swampert-engine`, con Postgres migrado y sembrado) y `CORS_ORIGIN` del engine incluyendo el origen del dev server del cliente.
2. Ir a `/dashboard/kpis` sin sesión → confirmar redirect a `/login`.
3. Loguearse con un usuario sembrado `active = true` (contraseña `swampert-dev-password`, `drizzle/customs/seeders/auth.seeder.ts`) → confirmar redirect a `/dashboard/kpis` y que las tarjetas muestran datos reales (no ceros ni placeholders).
4. Cambiar el rango de fechas en KPIs a un subconjunto de los 12 meses sembrados → confirmar que las tarjetas y el gráfico de Tendencias cambian sin un nuevo request de red visible más allá de la carga inicial (verificable en las devtools del navegador, pestaña Network).
5. Ir a Análisis detallado → confirmar que ambas secciones muestran datos, y que cambiar el rango de fechas afecta solo la sección de errores, no la de tareas por swarm.
6. En KPIs, click en "Actualizar reportes" con el período del mes actual → confirmar que el botón dispara `POST /api/reports/refresh`, que la respuesta es `{status: "accepted"}`, y que los datos mostrados se vuelven a pedir después.
7. Cerrar sesión (o borrar el token manualmente) e intentar volver a `/dashboard/trends` → confirmar redirect a `/login`, y que ningún dato con datos de la sesión anterior queda visible.

## Riesgos / casos borde

1. **La aritmética del lado del cliente sobre filas ya agregadas es una interpretación deliberada de la restricción de §6, no un hecho obvio.** Sumar `executionCount` o promediar `avgDurationSeconds` a lo largo de los meses visibles en el cliente, después de haber recibido esas filas ya agregadas del servidor, no es lo mismo que calcular el agregado desde `core.executions`/`trace.token_costs` — pero un evaluador podría cuestionarlo si no se explica así en la revisión oral. Vale la pena poder justificarlo verbalmente (`approach.md` §8.7 pide justificar cada pieza, no solo que funcione).
2. **`swarm_task_summary` no tiene columna `period`.** Si el filtro de rango de fechas se implementa como un componente compartido entre las 3 pantallas sin cuidado, es fácil terminar con un control de fecha en Análisis detallado que aparenta afectar la sección de tareas por swarm sin hacerlo realmente — eso es peor que no tener el control ahí. La UI debe dejar explícito que esa sección es un snapshot del estado actual, no filtrable por fecha.
3. **Refrescar reportes desde la UI afecta a todos los tenants, no solo al que está logueado.** `sp_refresh_reports` recalcula el período para **todos** los tenants en un único `CALL` (`deltas/reports.spec.md` § Contexto técnico) — el botón "Actualizar reportes" de un tenant recalcula silenciosamente los datos de los demás también. No es un bug de este dashboard, es el contrato del procedimiento; vale la pena poder explicarlo en la demo si se pregunta por qué el botón no lleva un selector de tenant.
4. **El JWT no se refresca ni se revalida proactivamente.** Si expira (`JWT_EXPIRES_IN`, default `1h` en el engine) mientras el usuario navega el dashboard, la siguiente llamada a cualquier endpoint de `reports/*` devuelve `401` — este spec no define un interceptor de renovación automática; el comportamiento esperado en esta pasada es que el `401` fuerce un logout y redirect a `/login`, no un error sin manejar.
5. **`.claude/rules/client.md` queda desactualizado por la incorporación de Pinia** (ver **Contexto técnico**) — cualquiera que lea esa regla después de esta pasada sin leer este spec asumirá que Pinia no está instalado. Señalado acá deliberadamente; la edición de `client.md` queda pendiente como una decisión separada del usuario, no resuelta en este spec.
6. **Ningún endpoint de `reports/*` está probado en vivo contra este dashboard todavía** — todo lo anterior está verificado contra el código fuente del engine (`deltas/reports.spec.md`, `deltas/restful.spec.md`), no contra una ejecución real del cliente. La sección **Cómo probar** de arriba queda pendiente de ejecutarse una vez implementado.
