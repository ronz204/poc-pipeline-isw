---
name: swampert-dashboard-ui
description: "Especificación de diseño y construcción para la UI faltante de swampert-client (Vue 3 + Vite + Pinia + Chart.js). Úsese al crear o modificar LoginView.vue, DashboardLayout.vue, KpisView.vue, TrendsView.vue, DetailView.vue, useChart.ts, o cualquier componente de presentación bajo source/features/reports o source/shared en este proyecto."
---

# UI del dashboard analítico — Swampert (Proyecto II, ISW-522)

## 0. Alcance de esta skill

Esta skill cubre **solo la capa visual** (`.vue`, `useChart.ts`, tokens de estilo) de
`projects/swampert-client`. NO modifica:
- `swampert-engine` (backend, ya completo y corriendo en `http://localhost:3000/api`).
- `source/shared/http/api.client.ts`, `auth.client.ts`, `auth.store.ts`, `reports.client.ts`,
  `useDateRangeFilter.ts`, `router.ts`, `main.ts` — todo esto ya existe, está probado, y se
  **consume tal cual**, nunca se reescribe.

Si en algún punto parece necesario tocar uno de esos archivos "ya completos", detente y
pregunta antes de hacerlo — probablemente el problema está en cómo se está consumiendo, no
en el archivo en sí.

## 1. Contrato del backend (fuente de verdad)

Base URL: `http://localhost:3000/api`. Todas las rutas salvo `/auth/login` requieren
`Authorization: Bearer <jwt>` (ya lo inyecta `ApiClient`); si falta o expiró, responden `401`
antes de tocar la base de datos.

| Endpoint | Notas |
|---|---|
| `POST /api/auth/login` | body `{tenantSlug, email, password}` → `200 {token, tenantId, userId, role}` \| `401 {error}` |
| `GET /api/reports/monthly-executions?period=<date>` | sin `period` → todos los meses del tenant (máx 12, ya sembrados) |
| `GET /api/reports/swarm-tasks?swarmId=<uuid>` | **snapshot del estado actual, sin dimensión de fecha** |
| `GET /api/reports/errors?period=<date>` | misma semántica que monthly-executions |
| `POST /api/reports/refresh` | body `{period: Date}` → recalcula **TODOS los tenants** de ese período, no solo el que llama |

Formas de fila:

```ts
// monthly-executions
{ tenantId: string; period: string; executionCount: number;
  avgDurationSeconds: string | null; totalCost: string; refreshedAt: string }

// swarm-tasks
{ tenantId: string; swarmId: string; taskStatus: string; taskCount: number; refreshedAt: string }
// taskStatus ∈ "pending" | "progress" | "completed" | "failed"

// errors
{ tenantId: string; period: string; severity: string; errorCount: number; refreshedAt: string }
// severity ∈ "low" | "medium" | "high" | "critical"
```

`period` es `date` como string `YYYY-MM-DD` (siempre día 1). `totalCost` y
`avgDurationSeconds` llegan como **string** (numeric de Postgres serializado) — parsear antes
de formatear, no asumir `number`.

## 2. Reglas de negocio no negociables (de `analytics-dashboard.spec.md`)

1. **3 pantallas por pestañas**, rutas bajo `/dashboard`: `kpis`, `trends`, `detail`.
2. **Filtro de rango de fechas 100% del lado del cliente.** El backend no tiene filtro de
   rango. `useDateRangeFilter.ts` (ya implementado) pide **una sola vez por carga de
   pantalla** el array completo sin filtrar, y recorta en el cliente al mover el rango.
   **Nunca volver a pedir datos al servidor por cada cambio de filtro.**
3. El filtro de fecha aplica a **KPIs, Tendencias y la sección de errores** de Análisis
   detallado — **NO** a la sección de tareas por swarm (`swarm-tasks` no tiene `period`, es
   snapshot). Esto debe quedar **explícito visualmente**: un badge o texto que diga que esa
   sección es "estado actual, no filtrable" — no basta con omitir el control ahí sin
   explicación.
4. `avgDurationSeconds === null` → mostrar explícitamente **"sin datos aún"**. Nunca forzarlo
   a `"0"` (leería como "instantáneo", es engañoso).
5. Botón **"Actualizar reportes"** (en KPIs): `POST /reports/refresh` con el período del mes
   actual del rango seleccionado, luego re-pide los datos. El copy debe comunicar
   honestamente que **recalcula todos los tenants**, no solo el logueado — es el contrato
   real, no un bug a esconder.
6. **Sin renovación automática de JWT.** Si expira (default 1h) y una llamada a `reports/*`
   da `401` → forzar logout + redirect a `/login`. No dejar un error crudo en pantalla.
7. **Login**: error de credenciales **deliberadamente genérico** — nunca decir si falló
   tenant, email o password (resistencia a enumeración). Un solo mensaje tipo
   "Credenciales inválidas".
8. Guard de rutas ya implementado en `router.ts` — la UI solo debe comportarse bien dentro de
   ese flujo, no reimplementar el guard.
9. **Chart.js sin wrapper.** Composable propio `useChart` que instancia `Chart` sobre un
   `ref<HTMLCanvasElement>` en `onMounted`, destruye en `onUnmounted`, actualiza
   (`chart.update()`) con un `watch` sobre los datos filtrados.
10. **RBAC no aplica en esta pasada** — mismo dashboard para `admin`/`member`/`viewer`.

## 3. Sistema de diseño (tokens)

No existe tema Tailwind hoy (`style.css` solo tiene `@import "tailwindcss";`). El favicon
violeta/celeste (`#863bff`/`#7e14ff`, `#47bfff`) es boilerplate heredado de un template
("Kelsen") — usarlo como referencia de partida, no como identidad obligatoria.

Dirección elegida: **consola de auditoría / sala de control**, no dashboard SaaS genérico.
El usuario audita agentes de IA — el lenguaje visual debe sentirse como una bitácora de
trazas, no una app de ventas.

### Color

| Token CSS | Hex | Uso |
|---|---|---|
| `--ink` | `#0f1420` | Fondo base |
| `--panel` | `#161d2e` | Tarjetas, superficies, sidebar |
| `--border` | `#26304a` | Bordes, divisores |
| `--text` | `#e8ebf3` | Texto primario |
| `--text-muted` | `#8891a8` | Labels, metadatos, timestamps |
| `--signal` | `#7c5cff` | Acción primaria, tab activo, serie de datos principal |
| `--trace` | `#22d3ee` | Dato recién refrescado / indicador "en vivo" |
| `--ok` | `#34d399` | `taskStatus: completed` |
| `--warn` | `#fbbf24` | `taskStatus: progress`, `severity: medium`, estados "sin datos aún" |
| `--critical` | `#f87171` | `taskStatus: failed`, `severity: critical` |

Mapear `severity`/`taskStatus` a estos colores de forma consistente en toda la app (una sola
función/objeto de mapeo, no repetir el mapeo en cada componente).

### Tipografía

- `Inter` (o similar) para UI, labels, copy.
- `JetBrains Mono` (o similar monoespaciada) **solo** para números y timestamps — refuerza
  que son datos crudos de auditoría, no una tarjeta de marketing.

### Layout

- Sidebar izquierdo fijo: logo, tenant activo, 3 tabs (`RouterLink` a kpis/trends/detail), y
  botón "Cerrar sesión" (§7.f) separado visualmente al fondo del sidebar.
- Topbar: selector de rango de fechas (estado compartido entre las 3 vistas vía
  `useDateRangeFilter`), visible en KPIs y Tendencias, y sobre la sección de errores en
  Detalle.
- `LoginView.vue` no usa sidebar/topbar (no hay sesión aún): tarjeta centrada sobre `--ink`.

### Elemento firma

**Trace strip**: tira horizontal de ticks (un segmento por mes del rango filtrado, color
`--signal` para meses con datos completos, `--trace` para el mes más reciente/en curso,
`--border` para meses fuera de rango) debajo de las tarjetas KPI. Referencia visual directa
al concepto de "bitácora/auditoría".

En el desglose por swarm (Detalle): usar **nodos circulares** (glifo de agente) en vez de
barras genéricas, con el color mapeado a `taskStatus`. En el desglose de errores: barras
normales por severidad, ya que ahí la comparación de magnitud es lo importante, no la
identidad del agente.

## 4. Inventario de archivos a construir

| Archivo | Estado | Descripción |
|---|---|---|
| `source/shared/useChart.ts` | crear | composable de ciclo de vida Chart.js (ver regla #9) |
| `source/shared/dashboardRange.ts` | crear | símbolos + tipo del rango compartido vía provide/inject (§8.d) |
| `source/features/auth/tenantLabel.ts` | crear | persiste `tenantSlug` fuera del store, para mostrarlo en el sidebar (§8.b) |
| `source/features/auth/LoginView.vue` | reemplazar placeholder | ver §5.1 |
| `source/shared/DashboardLayout.vue` | reemplazar placeholder | shell: sidebar + topbar + `<RouterView />`, dueño del rango compartido |
| `source/features/reports/useReportsData.ts` | crear | composable módulo-cacheado: fetch único por pantalla + manejo centralizado de 401 (§8.c/e) |
| `source/features/reports/KpisView.vue` | reemplazar placeholder | ver §5.2 |
| `source/features/reports/TrendsView.vue` | reemplazar placeholder | ver §5.3 |
| `source/features/reports/DetailView.vue` | reemplazar placeholder | ver §5.4 |
| `source/features/reports/components/KpiCard.vue` | crear | presentación pura, recibe props |
| `source/features/reports/components/RefreshButton.vue` | crear | presentación + emit, sin fetch propio |
| `source/features/reports/components/TrendChart.vue` | crear | envuelve un `<canvas>` + `useChart`, con selector de métrica |
| `source/features/reports/components/SwarmTaskBreakdown.vue` | crear | nodos de agente en HTML/CSS puro (no Chart.js), sin filtro de fecha, badge explícito |
| `source/features/reports/components/ErrorSeverityBreakdown.vue` | crear | barras por severidad, sí filtrado |

Todos los componentes bajo `components/` reciben datos ya resueltos por props — **cero
llamadas HTTP propias**. El fetch vive en `useReportsData.ts`, consumido por las 3 vistas
(`KpisView`, `TrendsView`, `DetailView`).

## 5. Especificación por pantalla

### 5.1 LoginView.vue

- Formulario: `tenantSlug` → `email` → `password`, en ese orden (se elige la organización
  antes que las credenciales dentro de ella).
- Submit llama `useAuthStore().login()`. Éxito → redirect a `/dashboard/kpis`.
- Error (401) → un único mensaje genérico "Credenciales inválidas" (regla #7). No inspeccionar
  el body del error para decidir un mensaje distinto por campo.
- Sin sidebar/topbar. Tarjeta centrada, fondo `--ink`.

### 5.2 KpisView.vue

- Al montar: pide `monthlyExecutions()` **una sola vez** (sin `period`, trae los ~12 meses).
- Aplica `useDateRangeFilter` sobre ese array para el rango seleccionado en el topbar.
- 3 `KpiCard`: ejecuciones totales (suma de `executionCount` en rango), duración promedio
  (ver criterio cerrado en §7 — promedio parcial + etiqueta si hay meses `null`), costo total
  (suma de `totalCost`, parseado a número, formateado según §7).
- `RefreshButton`: al click, `POST /reports/refresh` con `period` = primer día del mes actual
  del rango, luego re-fetch. Copy honesto sobre alcance multi-tenant (regla #5).
- Trace strip debajo de las tarjetas.

### 5.3 TrendsView.vue

- Mismos datos que KPIs, vía `useReportsData.ts` (§7.e) — no vuelve a pedir la red.
- `TrendChart.vue`: línea de una sola métrica a la vez (`executionCount` ↔ `totalCost`, con
  selector — ver §7), a lo largo de los meses en rango, vía `useChart`.

### 5.4 DetailView.vue

- Dos secciones lado a lado (o apiladas en mobile):
  - `SwarmTaskBreakdown`: pide `swarmTasks()`, **sin aplicar** `useDateRangeFilter`. Badge
    visible "estado actual — no filtrable" (regla #3). Nodos de agente coloreados por
    `taskStatus`.
  - `ErrorSeverityBreakdown`: pide `errors()`, sí aplica `useDateRangeFilter`. Barras por
    `severity`.

## 6. Convenciones de código

- Solo Composition API, `<script setup lang="ts">`. Nada de Options API.
- Clases para servicios (ya existen, no tocar) — composables (funciones) para todo lo
  reactivo nuevo. No mezclar estilos.
- `erasableSyntaxOnly` activo: nada de parameter properties en constructores
  (`constructor(private x: T)` no compila) ni `enum` — campos explícitos en el constructor,
  uniones de string literal en vez de `enum`.
- Alias ya declarados en `tsconfig.app.json` y `vite.config.ts`: `@shared/*`, `@features/*`,
  `@assets/*`, `@designs/*`. Usarlos, no inventar nuevos si no hace falta.
- Modo estricto: `noUnusedLocals`, `noUnusedParameters`, `noFallthroughCasesInSwitch`.
- Pinia **únicamente** para `auth.store.ts`. El filtro de fechas y cualquier otro estado de
  UI es composable local, no agregar stores nuevas.
- Tailwind v4 puro, sin librería de componentes instalada — construir con utilidades, tokens
  del §3 como variables CSS en `style.css` o `@theme` de Tailwind v4.

## 7. Decisiones cerradas (resuelven ambigüedades detectadas por Claude Code)

Estas decisiones son vinculantes — no volver a "evaluar" estos puntos durante la
implementación, ya están cerradas.

**a) Nombre de swarm.** No existe ningún endpoint que devuelva un nombre para `swarmId`
(confirmado contra `restful.spec.md`). `SwarmTaskBreakdown` etiqueta cada nodo con
`swarmId.slice(0, 8)` + `…`, y el UUID completo en el atributo `title` (tooltip nativo).
Limitación conocida y aceptada, no es un bug a resolver acá.

**b) Tenant activo en el sidebar.** `auth.store.ts` (intocable) no persiste `tenantSlug`. Se
crea `source/features/auth/tenantLabel.ts`: expone `setTenantLabel(slug)` /
`getTenantLabel()` sobre una clave de `localStorage` propia (ej. `swampert.tenantLabel`),
separada del store. `LoginView.vue` llama `setTenantLabel()` con el valor que el usuario
tipeó justo antes de redirigir a `/dashboard/kpis`. `DashboardLayout.vue` lee con
`getTenantLabel()` — si no hay valor (ej. sesión restaurada de una `localStorage` vieja sin
este campo), mostrar el `tenantId` (UUID) como fallback, nunca dejar el espacio vacío.

**c) 401 en medio de la sesión → logout centralizado.** Se crea
`source/features/reports/useReportsData.ts`: envuelve las 4 llamadas de
`ReportsApiClient` (`monthlyExecutions`, `swarmTasks`, `errors`, `refresh`). Cualquier
`ApiError` con `.status === 401` dispara, en un único lugar, `useAuthStore().logout()` +
`router.push('/login')`. Ninguna vista ni componente hace su propio `try/catch` de 401 —
todas pasan por este composable.

**d) Rango de fechas compartido entre las 3 vistas.** `useDateRangeFilter.ts` (intocable) no
acepta un rango externo — crea uno local cada vez que se invoca. Se crea
`source/shared/dashboardRange.ts` con una `InjectionKey<Ref<[Date, Date] | null>>`.
`DashboardLayout.vue` (no se desmonta al cambiar de pestaña hija) crea el `ref` y lo hace
`provide`; cada vista lo consume con `inject` y lo pasa como el rango a aplicar sobre el
array que le devuelve `useDateRangeFilter`. Un solo control de fecha, en el topbar de
`DashboardLayout.vue`, muta ese `ref` — las 3 vistas reaccionan al mismo cambio.

**e) Fetch duplicado entre KPIs y Tendencias.** Resuelto por el mismo `useReportsData.ts` de
(c): usa un cache a **nivel de módulo** (no Pinia — sigue siendo composable, solo que el
estado vive fuera de la función para sobrevivir entre llamadas desde distintas vistas) para
`monthlyExecutions()`, así `KpisView` y `TrendsView` comparten una sola llamada de red por
carga de `/dashboard/*`. **El cache está keyed por `tenantId`** (`Map<string, Row[]>`, no un
único array suelto) — nunca devolver datos cacheados de un `tenantId` distinto al actual. Al
disparar `logout()` (tanto por 401 como por el botón manual de §7.f) el mismo
`useReportsData.ts` **limpia el cache completo** (`cache.clear()`), no solo el logout del
store — así un login posterior de un tenant distinto en la misma pestaña del navegador nunca
puede mostrar datos residuales de la sesión anterior.

**f) Cerrar sesión manualmente.** No es intencional depender solo de la expiración del JWT.
Se agrega un botón "Cerrar sesión" en el sidebar de `DashboardLayout.vue` (debajo de las 3
pestañas, separado visualmente) que llama `useAuthStore().logout()` + limpia el cache de (e)
+ redirige a `/login`. Es la misma ruta de código que el logout automático por 401 de (c) —
un único punto de salida, no dos implementaciones paralelas.

**Botón "Actualizar reportes" — qué período manda.** Es el **mes calendario real de hoy**
(`new Date()`, normalizado a día 1), no el último mes del rango filtrado por el usuario. Es
el comportamiento más defendible frente al contrato real del backend ("recalcula el período
X para todos los tenants") y evita que el filtro de UI del usuario altere sin querer qué
período se recalcula a nivel global.

**Duración promedio con meses `null` en el rango.** Promediar solo los meses con
`avgDurationSeconds` no-null. Si al menos un mes visible es `null`, la tarjeta muestra el
promedio parcial con una etiqueta explícita: "promedio parcial (X de Y meses)". Si **todos**
los meses visibles son `null`, mostrar "sin datos aún" sin número.

**TrendChart — qué serie mostrar.** Una sola línea a la vez, con un selector simple
(ejecuciones ↔ costo) en vez de doble eje — menor complejidad, mejor legibilidad en un
gráfico chico.

**Tipografía.** No se instala ningún paquete nuevo (no autorizado en el spec). Se usa pila de
fuentes de sistema: `font-family: ui-monospace, "SFMono-Regular", monospace` para los datos
(rol "JetBrains Mono") y `system-ui, -apple-system, "Segoe UI", sans-serif` para el resto
(rol "Inter"). Si más adelante se autoriza instalar `@fontsource/*`, es un cambio de una
línea en `style.css`, no estructural.

**Selector de rango de fechas.** Dos `<input type="date">` nativos (no hay date-picker
instalado). Va en el topbar de `DashboardLayout.vue`, mutando el `ref` de §8.d.

**Detalles técnicos de `useChart.ts`.**
- Importar `import { Chart } from 'chart.js/auto'` (auto-registra controllers/escalas) — no
  `import { Chart } from 'chart.js'` a secas, que requiere registro manual y falla en
  silencio si se omite.
- Los tokens de color (`--signal`, `--ok`, etc.) no se resuelven solos dentro de un
  `<canvas>`: leerlos con `getComputedStyle(document.documentElement).getPropertyValue('--signal').trim()`
  al construir la config del chart, no hardcodear el hex duplicado en `useChart.ts`.

**Formato de valores.**
- `totalCost`: `Intl.NumberFormat('es-CR', { style: 'currency', currency: 'USD' })` sobre el
  valor parseado a `number`.
- `avgDurationSeconds`: convertir a formato `Xm Ys` (minutos y segundos), no mostrar segundos
  crudos.

## 8. Checklist de verificación antes de dar por terminado un componente

- [ ] ¿Este componente de presentación hace algún `fetch`/llamada a `ReportsApiClient`
      directamente? → si sí, moverlo a la vista padre.
- [ ] ¿Algún dato `null` (especialmente `avgDurationSeconds`) se está mostrando como `0` o
      vacío sin explicación?
- [ ] ¿La sección de swarm-tasks dejó claro visualmente que no responde al filtro de fecha?
- [ ] ¿El copy del botón de refresh menciona (aunque sea brevemente) que afecta a todos los
      tenants?
- [ ] ¿Un 401 durante la navegación en `/dashboard/*` termina en logout + `/login`, sin
      pantalla de error cruda?
- [ ] ¿Se usaron los tokens de color del §3 en vez de colores Tailwind por defecto sueltos?
- [ ] ¿El rango de fechas viene del `provide`/`inject` de `dashboardRange.ts`, o se creó por
      error un rango local nuevo en la vista (regla §7.d)?
- [ ] ¿El fetch de `monthlyExecutions()` pasa por `useReportsData.ts`, o alguna vista lo pide
      directo con `ReportsApiClient` duplicando la llamada de red (regla §7.e)?
- [ ] ¿El cache de `useReportsData.ts` está keyed por `tenantId`, y se limpia por completo en
      cualquier logout (automático por 401 o manual por el botón) — no solo el store de auth
      (regla §7.e/f)?
- [ ] ¿Existe el botón "Cerrar sesión" en el sidebar y usa la misma ruta de código que el
      logout automático por 401, en vez de una implementación paralela (regla §7.f)?