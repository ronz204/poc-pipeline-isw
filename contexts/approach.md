# Swampert — Proyecto II: Requerimientos y restricciones técnicas

> Criterio teórico contra el que se evalúa si Proyecto II está completo, según el enunciado oficial (ISW-522, Proyecto II). No propone implementación — eso vive en otro documento. Los puntos de rúbrica se citan entre paréntesis (100 pts = 20% de la nota final) porque ayudan a calibrar cuánto rigor se espera de cada componente.

---

## Qué cambia respecto a Proyecto I

| Aspecto | Proyecto I | Proyecto II |
|---|---|---|
| Modelo de datos | Se diseña desde cero | Se **reutiliza sin cambios estructurales** |
| Capa nueva | — | Lógica procedimental + reportes derivados |
| Stack de aplicación | FastAPI / asyncpg / SvelteKit | **Drizzle / ElysiaJS / Vue** |
| Peso del esfuerzo | Modelado y seguridad | ~70% procedimientos/funciones/triggers, ~30% análisis/dashboard |

El cambio de stack es secundario frente al peso real de la evaluación: el enunciado declara explícitamente esa proporción 70/30 en sus notas finales.

---

## Distribución de la rúbrica

| Componente | Puntos |
|---|---|
| Procedimientos | 18 |
| Funciones | 15 |
| Triggers | 12 |
| Auditoría | 10 |
| Tablas de resumen | 12 |
| Dashboard | 15 |
| Documentación | 10 |
| Revisión oral | 8 |
| **Total** | **100** |

---

## 1. Procedimientos almacenados (18 pts)

Mínimo **5 procedimientos**. Cada uno debe representar la automatización de un proceso de negocio completo — no una operación trivial sobre una sola tabla, sino un flujo que en la vida real requeriría varios pasos coordinados y que hoy, sin el procedimiento, tendría que hacerse a mano.

- **Parámetros reales:** cada procedimiento recibe identificadores, cantidades o fechas y opera sobre ellos — nada de valores fijos ni hardcodeados.
- **Variedad de control:** no hace falta que un mismo procedimiento use IF/ELSE, WHILE, FOR y CASE a la vez, pero entre los 5+ debe aparecer cada tipo relevante al menos una vez. Un conjunto que solo usa IF/ELSE no cumple el espíritu del requisito, aunque cada uno esté bien escrito.
- **Validación de entrada:** cada uno verifica que los datos recibidos son válidos (existencia de referencias, estados coherentes, rangos razonables) y lanza una excepción declarada cuando no lo son.
- **Transacciones explícitas:** cuando un procedimiento modifica más de una tabla, lo hace con BEGIN/COMMIT/ROLLBACK, para que un error a mitad de camino no deje datos parcialmente escritos.
- **Documentación:** propósito, parámetros y un ejemplo de uso concreto por procedimiento.

---

## 2. Funciones definidas (15 pts)

Mínimo **8 funciones**, pensadas como piezas de lógica reutilizable.

- **Reutilización verificable:** cada función debe ser usada por al menos uno de los procedimientos del punto anterior. Una función que ningún procedimiento invoca no cumple el requisito, por bien escrita que esté.
- **Mix de tipos:**
  - *Escalares* — reciben parámetros y devuelven un único valor (número, fecha, booleano).
  - *Retornan tabla* — encapsulan consultas de lectura que se repiten en distintos contextos del sistema.
  
  No alcanza con tener solo un tipo de los dos.
- **Documentación:** qué recibe, qué retorna, y un ejemplo de uso.

---

## 3. Triggers (12 pts)

Mínimo **6 triggers**, cada uno disparado automáticamente ante un evento (INSERT, UPDATE o DELETE) — nunca invocado manualmente.

- **Rol 1 — Validación:** rechaza la operación cuando se viola una regla de negocio (ej. impedir una inserción que dejaría el sistema en un estado inválido).
- **Rol 2 — Mantenimiento de dato derivado:** actualiza un total, contador o estado dependiente como consecuencia directa de la operación que lo dispara.

Un trigger que no cumple ninguno de los dos roles no satisface el requisito, aunque técnicamente se dispare.

- **Documentación:** tabla en la que vive, evento que lo activa, y qué hace exactamente.

---

## 4. Auditoría automática (10 pts)

Sistema de auditoría independiente de los triggers de negocio del punto anterior.

- **Tabla `audit_log`:** tabla modificada, tipo de operación, usuario, momento exacto, y un resumen legible del cambio — no un volcado completo de la fila.
- **Registro automático:** triggers sobre las tablas principales del dominio que escriben en `audit_log` en cada cambio relevante, sin intervención manual.
- **Función de consulta:** equivalente conceptual a `ver_historial_tabla(nombre_tabla)`, que retorna todos los cambios registrados sobre una tabla dada.
- **Propósito declarado:** auditoría, seguridad y recuperación ante errores — hay que poder argumentarlo en la revisión oral, no solo que el mecanismo funcione.

---

## 5. Tablas de resumen / reportes (12 pts)

Entre **3 y 4 tablas** que consolidan datos operacionales en resúmenes útiles para análisis. A diferencia de las tablas del dominio, estas no buscan evitar redundancia ni cumplir formas normales — son agregados calculados para lectura rápida desde el dashboard.

- **Procedimiento de llenado:** al menos uno, capaz de recalcular un período completo (borrar + reinsertar, o UPSERT) en vez de acumular indefinidamente o duplicar registros en corridas sucesivas.
- **Trazabilidad:** todo valor que aparece en estas tablas debe poder reconstruirse consultando directamente las tablas operacionales de origen.

---

## 6. Dashboard de análisis (15 pts)

Capa de presentación de las tablas de resumen — se conecta directamente a ellas y **no hace cálculos propios en el momento de la consulta**. Esta restricción no es estética: es lo que permite cumplir el requisito de respuesta rápida (< 1 segundo), porque calcular agregados sobre la marcha dejaría de ser realista a medida que crece el volumen de datos.

- **2 a 3 pantallas**, navegables por pestañas o mecanismo equivalente:
  - **KPIs** — tarjetas con números grandes, lectura de un vistazo.
  - **Tendencias** — gráfico de línea con evolución de los últimos 12 meses.
  - **Análisis detallado** — tabla o gráfico de barras con desglose por categoría (puede ser una sección dentro de otra pantalla si se opta por solo 2).
- **Filtro funcional:** al menos rango de fechas, que efectivamente actualiza lo mostrado al aplicarse — no un control decorativo.

---

## 7. Documentación técnica (10 pts)

- **README general:** dominio, procesos automatizados, instalación e inicialización de la BD desde cero, cómo ejecutar procedimientos de prueba, notas técnicas. Debe declarar explícitamente el uso de IA generativa si aplica — condición de integridad académica, no un detalle opcional.
- **Documentos por componente:**
  - `PROCEDIMIENTOS` — lista y para qué sirve cada uno.
  - `FUNCIONES` — lista y qué retorna cada una.
  - `TRIGGERS` — cuáles existen y cuándo se disparan.
  - `TABLAS_RESUMEN` — qué contiene cada una.
  - `AUDITORIA` — cómo consultar el historial de cambios.
  - `CASOS_USO` — guía paso a paso de uso del sistema completo.

Esta documentación no es un anexo decorativo: es lo que permite que alguien externo al equipo, incluido el profesor durante la revisión, entienda el sistema sin leer el SQL línea por línea.

---

## 8. Revisión oral (8 pts)

30 minutos, en vivo, frente al profesor. El equipo debe poder:

1. Correr 2 o 3 procedimientos con datos reales y mostrar el INSERT/UPDATE resultante.
2. Ejecutar una función de cálculo y mostrar su resultado.
3. Provocar deliberadamente el rechazo de un trigger insertando un dato inválido.
4. Consultar el historial de auditoría: quién cambió qué y cuándo.
5. Correr el procedimiento de resumen y mostrar las tablas de consolidados actualizadas.
6. Navegar el dashboard completo cambiando filtros, verificando que responde a datos reales.
7. **Justificar verbalmente** cada procedimiento: qué problema de negocio resuelve.

La ausencia sin justificación de un integrante implica nota 0 para esa persona en particular.

---

## Fecha de entrega

**Semana 14 — miércoles 28 de agosto de 2026.**

El cronograma de hitos intermedios es consistente con esta fecha, sin ambigüedad entre secciones del enunciado:

| Hito | Contenido | Semana |
|---|---|---|
| 1 | 5 procedimientos implementados y probados | 9 |
| 2 | 8 funciones; 6+ triggers; auditoría activa | 10-11 |
| 3 | Tablas de resumen + procedimientos que las llenan | 12 |
| 4 | Dashboard conectado mostrando datos en vivo | 13 |
| Final | Entrega completa | 14 (28 ago) |

A diferencia de Proyecto I, acá no hace falta reconciliar fechas contradictorias entre distintas secciones del documento.