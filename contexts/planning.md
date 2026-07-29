# Swampert — Metodología de planificación de tareas

> Cómo se define, especifica y cierra una tarea de implementación en Swampert. No es teoría: es la plantilla que rige todo archivo `*.plan.md` del repo, y que Claude debe tener presente antes de tocar código en cualquier tarea no trivial.

---

## 📁 Convención `*.plan.md`

Cualquier documento de planificación en el repo — sin importar en qué carpeta viva — se nombra con el sufijo `.plan.md` (ej. `tasks.plan.md` dentro de un proyecto). Ese sufijo es la señal: si un archivo termina en `.plan.md`, su contenido sigue la plantilla de este documento. No hay un único archivo canónico ni una ubicación fija — puede haber uno por proyecto (`projects/swampert-engine/tasks.plan.md`, `projects/swampert-client/tasks.plan.md`), o varios dentro del mismo proyecto si tiene sentido separarlos (por ejemplo, uno para el modelo de datos/procedimientos y otro para el dashboard). Los archivos concretos van y vienen — se cierran, se borran, se reemplazan por el siguiente lote de tareas —; lo que no cambia es el formato, y ese formato vive acá.

Antes de implementar algo no trivial, buscar (`Glob **/*.plan.md`) si ya existe un plan relevante en el repo, no asumir una ruta fija.

---

## 🧭 Por qué existe esto

Swampert es un proyecto académico (ISW-522, Proyecto II) con fecha de entrega fija (28 de agosto de 2026, semana 14) y una rúbrica que reparte 100 puntos entre componentes muy distintos entre sí: procedimientos, funciones, triggers, auditoría, tablas de resumen, dashboard y documentación (ver `problems.md` y el detalle de puntos en `approach.md`). El riesgo real no es que un componente individual salga mal — es llegar a una semana de hito sin que la anterior esté genuinamente cerrada, porque "cerrado" nunca quedó definido de antemano. Con hitos intermedios ya fijados por el cronograma (semana 9: procedimientos; 10-11: funciones/triggers/auditoría; 12: tablas de resumen; 13: dashboard), no cerrar un hito a tiempo empuja directamente el siguiente.

La corrección no es más disciplina, es más especificación: **cada tarea sale del día con spec propio antes de tocar código**, y ese spec deja explícito qué significa "terminado" antes de escribir la primera línea. Un checklist binario al final de la tarea es mucho más difícil de auto-engañar que una sensación de "ya casi" — y acá "ya casi" es particularmente peligroso porque varios criterios de la rúbrica son binarios en sí mismos (¿el procedimiento usa transacción explícita, sí o no? ¿el trigger cumple uno de los dos roles, sí o no?).

**Cuántas tareas por día:** `N` vive entre 2 y 4, ajustable según qué tan cargada esté la semana del cronograma. Si el formato resulta liviano de mantener, subir el número es la progresión esperada; si dos tareas con este nivel de detalle ya ocupan el día completo (algo probable en componentes densos como procedimientos o triggers, donde cada uno pide validación, control de flujo variado y documentación), quedarse en un número bajo es la señal correcta, no una falla.

---

## 📋 La plantilla — 8 secciones obligatorias

Una tarea no entra a ningún `*.plan.md` si le falta alguna de estas ocho secciones. El orden importa: cada una depende de que la anterior ya esté resuelta.

1. **Objetivo** — una frase, el resultado observable, no la actividad. ("Que `registrar_ejecucion` valide la tarea referenciada y falle con excepción declarada si no existe", no "trabajar en el procedimiento de ejecuciones".) Si el objetivo se puede escribir como una lista de sub-tareas, todavía no es un objetivo, es un plan disfrazado.
2. **Alcance** — qué entra y qué explícitamente no entra hoy. La mitad que importa es la segunda: nombrar por escrito lo que se pospone (y por qué es seguro posponerlo) es lo que evita que la tarea se infle a mitad de camino o que alguien asuma después que algo quedó cubierto cuando no fue así. Es especialmente relevante acá separar "modelado" de "permisos" (ver `database.md` § Migraciones) — una tarea de DDL no necesita resolver el granting en el mismo golpe.
3. **Contexto técnico** — qué ya existe en el repo que la tarea toca o de lo que depende: archivos concretos, líneas, decisiones ya tomadas en otros `contexts/*.md` (`concepts.md` para el porqué teórico, `database.md` para convenciones de schema/roles/RLS, `approach.md` para qué exige la rúbrica de ese componente puntual). Esto es lo que hace que la tarea sea ejecutable por cualquiera (incluido Claude en una sesión sin memoria de las anteriores) sin tener que re-explorar el repo desde cero.
4. **Implementación** — pasos concretos, archivos a crear/tocar, en orden. No es pseudocódigo completo, pero sí lo suficientemente específico para que la secuencia de decisiones ya esté tomada antes de abrir el editor. Para migraciones SQL, esto incluye el número y nombre de archivo exacto (`NNNN-modeling-*.sql` / `NNNN-granting-*.sql`) siguiendo la convención de `database.md`.
5. **Config / secretos** — variables de entorno nuevas o afectadas, y de dónde sale su valor esperado. Se separa del resto porque es lo que más silenciosamente rompe un ambiente que no es el que probó el desarrollador — relevante acá porque hay tres roles de Postgres (`sampler`/`runner`/`backuper`) con credenciales propias, y confundir cuál usa el backend rompe RLS en silencio.
6. **Criterios de aceptación** — checklist binario (`- [ ]`), no "andá probando". Cada ítem tiene que poder marcarse sí/no sin juicio de por medio. Si un criterio necesita interpretación para saber si pasó, está mal escrito. Cuando la tarea toca un componente de la rúbrica, los criterios de esa sección de `approach.md` (parámetros reales, transacción explícita, documentación con ejemplo, etc.) se listan acá explícitamente — no basta con "implementado", tiene que quedar claro qué exigencia puntual de la rúbrica cubre.
7. **Cómo probar** — comando o flujo manual exacto para verificar, paso a paso. No "probar el procedimiento", sino el `CALL`/`SELECT` concreto, con qué parámetros, y qué se espera ver como resultado o como excepción.
8. **Riesgos / edge cases** — lo que puede fallar en silencio si no se piensa ahora: decisiones que se están tomando implícitamente y conviene dejar explícitas (ej. "¿qué pasa si se intenta registrar un costo de tokens para una ejecución que ya está en estado `completada`?"), interacción con RLS (¿el `SET LOCAL app.current_tenant_id` está garantizado antes de que corra esta lógica?), y volumen o rendimiento cuando la tabla involucrada es de `trace` (candidata a particionamiento, ver `concepts.md`).

**Estado** de cada tarea se marca en la tabla resumen del documento: 🔲 pendiente · 🟡 en progreso · ✅ hecho. La tabla resumen (con solo # / Tarea / Estado) va arriba del documento; el detalle de cada tarea va debajo, en su propia sección.

---

## 🤖 Cómo debe usar esto Claude

- **Antes de implementar** cualquier tarea no trivial (procedimiento, función, trigger, migración de schema, pantalla del dashboard), revisar si ya existe un `*.plan.md` relevante en el repo (buscarlo, no asumir que no existe). Si existe, seguir su spec — no reinterpretar el alcance sobre la marcha.
- **Si el usuario pide implementar algo que todavía no tiene spec**, y el trabajo no es trivial, proponer primero escribir la tarea siguiendo esta plantilla (las 8 secciones) antes de tocar código — igual que se haría con un plan, pero con este formato específico en vez de uno genérico.
- **No saltarse secciones** para ir más rápido. La plantilla es cara de escribir a propósito: el costo de especificar está para evitar el costo mayor de descubrir el alcance real a mitad de la implementación, o peor, de llegar a la revisión oral sin poder justificar por qué un componente cumple la rúbrica.
- Esto convive con — no reemplaza — el modo Plan normal de Claude Code. Para tareas exploratorias o cuando todavía no está claro qué se va a construir, seguí usando Plan. Esta plantilla aplica una vez que la tarea ya está lo bastante definida como para especificarse por escrito.
