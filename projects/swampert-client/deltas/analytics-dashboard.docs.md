# Dashboard analítico — Reporte de implementación

> Qué se construyó, qué se arregló, y contra qué se verificó. Explicado en simple,
> con las rutas de los archivos relevantes, para que el equipo pueda ubicarse rápido
> sin tener que leer el código línea por línea. El diseño y las reglas de negocio que
> esto implementa están definidas en `analytics-dashboard.spec.md` (el spec original)
> y `swampert-dashboard-ui-skill.md` (las decisiones de diseño visual) — este
> documento es el resumen de "qué se hizo realmente", no reemplaza a esos dos.

---

## 1. Resumen en una frase

Antes de esta sesión, `swampert-client` tenía toda la lógica de conexión al backend
lista (login, llamadas a la API, filtro de fechas) pero **cero interfaz visual** —
las 5 pantallas eran literalmente `<div>TODO: ...</div>`. Ahora las 3 pantallas del
dashboard (KPIs, Tendencias, Detalle) más el login están completamente construidas,
verificadas contra datos reales, y sin ningún cambio al backend.

## 2. Qué había antes vs. qué hay ahora

| Archivo | Antes | Ahora |
|---|---|---|
| `source/features/auth/LoginView.vue` | Placeholder | Formulario real (organización/correo/contraseña) |
| `source/shared/DashboardLayout.vue` | Placeholder | Sidebar + topbar con filtro de fecha + logout |
| `source/features/reports/KpisView.vue` | Placeholder | 3 tarjetas + trace strip + bitácora mensual + botón de refresh |
| `source/features/reports/TrendsView.vue` | Placeholder | Gráfico de línea con selector de métrica |
| `source/features/reports/DetailView.vue` | Placeholder | Desglose de swarms (nodos + tabla + barras) y errores por severidad |

## 3. Pantalla por pantalla

### Login (`source/features/auth/LoginView.vue`)
Formulario con organización → correo → contraseña, en ese orden. Si las credenciales
fallan, siempre muestra el mismo mensaje genérico ("Credenciales inválidas") sin decir
cuál de los 3 datos estaba mal — es a propósito, así nadie puede usar el formulario
para adivinar qué organizaciones o correos existen.

### Layout general (`source/shared/DashboardLayout.vue`)
El armazón que envuelve las 3 pantallas: sidebar con el nombre de la organización y
las 3 pestañas, topbar con el selector de rango de fechas (dos campos de fecha nativos),
y el botón de "Cerrar sesión" abajo del todo. El rango de fechas que se elige acá es
**compartido entre las 3 pantallas** — cambiarlo en una se refleja en las otras dos sin
recargar nada.

### KPIs (`source/features/reports/KpisView.vue`)
- 3 tarjetas grandes: ejecuciones totales, duración promedio, costo total —
  calculadas sobre el rango de fechas elegido.
- **Trace strip**: una tira de segmentos, uno por mes con datos — morado si está en tu
  rango, cian si es el mes más reciente.
- **Bitácora mensual** (`source/features/reports/components/MonthlyLogbook.vue`):
  una fila por mes con su costo, duración y hace cuánto se recalculó. La fila más
  reciente se destaca en cian con un destello visual cuando se actualiza.
- **Botón "Actualizar reportes"** (`source/features/reports/components/RefreshButton.vue`):
  llama al procedimiento de recálculo del backend para el mes actual.

### Tendencias (`source/features/reports/TrendsView.vue`)
Gráfico de línea (`components/TrendChart.vue`, con Chart.js) mostrando la evolución
mensual, con un selector para alternar entre ver ejecuciones o costo.

### Detalle (`source/features/reports/DetailView.vue`)
Dos columnas:
- **Izquierda**: tareas por swarm, en dos formatos — nodos de colores
  (`components/SwarmTaskBreakdown.vue`, con una tabla real debajo de los nodos) y
  barras apiladas por estado (`components/SwarmTaskBars.vue`). Esta sección **nunca**
  responde al filtro de fecha — se lo avisa con un punto cian pulsante junto al
  título, porque son datos del estado actual, no un histórico.
- **Derecha**: errores por severidad (`components/ErrorSeverityBreakdown.vue`) —
  barras por nivel de gravedad más un resumen (total, severidad más frecuente, mes
  con más errores).

## 4. Piezas compartidas (no son pantallas, son la base de todo)

| Archivo | Para qué sirve |
|---|---|
| `source/features/reports/useReportsData.ts` | Centraliza todas las llamadas al backend, el caché (para no repetir pedidos entre pantallas), y el logout automático si la sesión expira |
| `source/shared/dashboardRange.ts` | El mecanismo que comparte el rango de fecha entre las 3 pantallas |
| `source/features/reports/useSyncedDateRange.ts` | Conecta ese rango compartido con el filtro de cada pantalla |
| `source/features/reports/statusColors.ts` | Un solo lugar que define qué color y qué texto le corresponde a cada estado de tarea o severidad de error — evita repetir esa lógica en cada componente |
| `source/features/auth/tenantLabel.ts` | Guarda el nombre de la organización (el backend solo guarda su ID) para mostrarlo en el sidebar |
| `source/shared/useChart.ts` | El código que crea/destruye los gráficos de Chart.js de forma segura |

## 5. Identidad visual

Dirección elegida: "consola de auditoría" — fondo oscuro, acentos morado (acción
principal) y cian (dato recién actualizado), números y fechas en fuente
monoespaciada. Los colores están definidos una sola vez en `source/style.css` como
variables, y de ahí Tailwind genera automáticamente clases como `bg-panel`,
`text-muted`, `border-line`, etc. — nunca hay un color hardcodeado suelto en un
componente.

## 6. Bugs reales que se encontraron y se corrigieron

Estos no aparecieron leyendo el código — aparecieron probando la app en vivo con
datos reales, comparando lo que mostraba la pantalla contra la base de datos
directamente:

1. **Los meses en el gráfico de Tendencias aparecían corridos uno hacia atrás**
   (agosto se mostraba como julio). Causa: una fecha tipo `"2026-08-01"` se estaba
   interpretando en la zona horaria del navegador en vez de UTC. Se corrigió en
   `TrendChart.vue`, `MonthlyLogbook.vue` y `ErrorSeverityBreakdown.vue`.
2. **Un rango de fechas invertido** (inicio después del fin) dejaba las 3 pantallas
   vacías sin ningún aviso. Ahora `DashboardLayout.vue` valida esto y muestra un
   mensaje claro en rojo en vez de fallar en silencio.
3. **El badge "actualizado ahora"** se quedaba pegado diciendo eso aunque hubieran
   pasado horas desde el último refresh. Ahora desaparece solo pasados 2 minutos.

## 7. Cómo se verificó (no solo "compila")

- Compilación de producción real (`bun run build`) sin errores.
- Cero errores de consola del navegador en las 3 pantallas.
- Login, filtro de fechas, botón de refresh y logout probados en vivo contra el
  backend real, con usuarios y datos sembrados de verdad.
- Varios números mostrados en pantalla se compararon a mano contra consultas
  directas a Postgres para confirmar que coinciden exacto (no solo que "se ven
  razonables").
- El botón "Actualizar reportes" se verificó de punta a punta: se confirmó en la
  base de datos que el timestamp `refreshed_at` de la fila correspondiente cambia
  de verdad al hacer click, no solo que aparece un mensaje en pantalla.

## 8. Cuentas de prueba, para que el equipo pruebe el dashboard

Todos los usuarios sembrados comparten la misma contraseña:

```
swampert-dev-password
```

Los datos son aleatorios por organización (se sembraron una sola vez con
`bun run drizz:seeding`), así que cada una tiene actividad en meses distintos.
Verificado directo contra la base de datos, no de memoria:

| Organización | Correo | Rango de fechas recomendado | Qué vas a ver |
|---|---|---|---|
| `driftwood-ai` | `antagonistic_enedina@libero.it` | 01/07/2026 – 31/08/2026 | 2 meses con datos (jul y ago 2026); 1 error en agosto (media) |
| `helix-orchestrator` | `welcoming_viktoria@hotmail.com` | 01/09/2025 – 31/01/2026 | 4 meses con datos; el único error (enero, media) cae adentro del rango |
| `nimbus-swarm` | `burly_dannielynn@orange.fr` | 01/03/2026 – 30/04/2026 | El mejor caso para ver errores: marzo (media:1) + abril (media:2), 3 errores juntos en pantalla |
| `quanta-labs` | `unsuited_rayleigh@wanadoo.fr` | 01/09/2025 – 31/03/2026 | Incluye un error de severidad baja (sept) y uno alto (marzo) — la única con 2 severidades distintas visibles a la vez |
| `iron-hive` | `opinionated_deysi@web.de` | 01/11/2025 – 31/07/2026 | Solo 2 meses con datos en todo el año — útil para demostrar el caso de "casi sin actividad" |

**Importante — no uses `solace-systems` para el login.** No tiene ningún usuario
activo en la base (todos quedaron `active = false` al azar al sembrar) — el login
siempre va a devolver "Credenciales inválidas" ahí, sin importar la contraseña.
No es un bug de la UI, es un hueco real de los datos sembrados. Es una lástima
porque tiene los datos más ricos (9 meses, 5 errores en 4 meses distintos con 3
severidades) — si en algún momento el equipo quiere activar un usuario ahí a mano
para la demo, es la organización con mejor variedad de datos.

**Para demostrar el caso "sin datos" a propósito**: con cualquiera de las 5
organizaciones de arriba, elegí un rango que caiga en un mes que **no** esté en su
lista (por ejemplo, mayo 2026 con `nimbus-swarm`) — el dashboard va a mostrar "0" y
"sin datos aún" correctamente, útil para explicar en la revisión oral que el
sistema no inventa números donde no hay dato real.

**Tip al elegir fechas**: siempre usá el día 1 del mes como fecha de inicio. Los
datos se guardan con fecha fija en el día 1 de cada mes — si el rango empieza, por
ejemplo, el 3, ese mes puede quedar excluido aunque la intención sea incluirlo
completo.

## 9. Dos arreglos de infraestructura (no son parte de la UI, pero se encontraron auditando)

- **`.gitattributes`** (nuevo, en la raíz del repo): protege
  `services/postgres/scripts/00-bootstrap.sh` de un bug real de finales de línea
  (CRLF vs LF) que impedía que Postgres arrancara — sin este archivo, cualquiera
  que clonara el repo en Windows con cierta configuración de Git podía
  reintroducir el mismo bug sin darse cuenta.
- **`projects/swampert-client/.gitignore`**: ahora excluye `.env` y variantes
  (antes no lo hacía, a diferencia del `.gitignore` del engine, que sí).

## 10. Cumplimiento contra lo pedido

**Contra `analytics-dashboard.spec.md`** (el spec original): los 11 criterios de
aceptación de ese documento están cumplidos y verificados en vivo — login, guard de
rutas, las 3 pantallas, filtro sin re-pedir datos al servidor, botón de refresh,
caso `avgDurationSeconds: null`, no-filtro en tareas por swarm, y Pinia usado solo
para la sesión.

**Contra el enunciado oficial** (`Proyecto II.docx`, sección 3.6 y la rúbrica de
Dashboard): 2-3 pantallas ✓, KPIs con tarjetas grandes ✓, tendencia de 12 meses ✓,
"tabla o gráfico de barras" en el desglose detallado ✓ (hay ambas cosas: la tabla de
swarms y las barras de errores), filtro de fecha funcional ✓, respuesta rápida sin
cálculo en el servidor ✓.

**Un matiz para tener listo de palabra en la revisión oral**: el enunciado dice que
el dashboard "no hace cálculos, solo muestra datos" — las tarjetas de KPI sí suman/
promedian filas que el servidor *ya* devolvió agregadas por mes (no recalculan desde
las tablas operacionales). Es una diferencia real, defendible, pero vale la pena
poder explicarla si preguntan.

## 11. Qué NO se tocó

`swampert-engine` (backend, base de datos, procedimientos, API) no se modificó en
absoluto. Todo lo de este documento es exclusivamente `swampert-client`.

## 12. Pendiente para el equipo — declaración de uso de IA

El enunciado del proyecto exige declarar explícitamente el uso de IA generativa en
el README (`approach.md` / `Proyecto II.docx`, condición de integridad académica).
Toda la UI descrita acá se construyó con asistencia de Claude Code — hoy el
`README.md` de la raíz del repo **no tiene ninguna declaración de esto todavía**.
Vale la pena que el equipo agregue esa mención antes de la entrega final.

## 13. Archivos nuevos de esta sesión (referencia rápida)

```
projects/swampert-client/
├── source/shared/
│   ├── useChart.ts
│   └── dashboardRange.ts
├── source/features/auth/
│   └── tenantLabel.ts
└── source/features/reports/
    ├── statusColors.ts
    ├── useReportsData.ts
    ├── useSyncedDateRange.ts
    └── components/
        ├── KpiCard.vue
        ├── RefreshButton.vue
        ├── TrendChart.vue
        ├── MonthlyLogbook.vue
        ├── SwarmTaskBreakdown.vue
        ├── SwarmTaskBars.vue
        └── ErrorSeverityBreakdown.vue
```

Más `.gitattributes` (raíz del repo) y el `.gitignore` actualizado de
`swampert-client`.
