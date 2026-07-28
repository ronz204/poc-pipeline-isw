# Swampert — Problemas que resuelve

## El contexto: agentes de IA que ya no son "uno solo"

Cuando una empresa empieza a usar IA en serio, rara vez se queda con "un chatbot". Lo normal es que termine con **varios agentes trabajando juntos**: uno que investiga, otro que escribe, otro que revisa, otro que ejecuta acciones. A eso le llamamos un **enjambre** (swarm). El problema es que, a medida que estos enjambres crecen, aparecen preguntas muy difíciles de responder sin las herramientas correctas:

- ¿Qué agente hizo qué, y en qué orden?
- ¿Por qué falló esta ejecución? ¿Fue el agente 2 o el agente 4?
- ¿Cuánto nos está costando en tokens cada tarea que resolvemos con IA?
- ¿Quién de la empresa tiene permiso para ver esta información, y quién no?
- Si algo salió mal, ¿podemos reconstruir exactamente la cadena de decisiones que llevó a ese error?

Sin un sistema pensado para responder estas preguntas, las empresas quedan **operando a ciegas**: confían en que los agentes van a funcionar bien, pero no tienen forma de comprobarlo, auditarlo ni controlarlo cuando algo se rompe o se dispara el gasto.

## El problema, en una frase

**Las empresas que usan enjambres de agentes de IA no tienen visibilidad ni control sobre lo que esos agentes hacen, cuánto cuestan, ni quién es responsable de qué.**

Es un problema de **observabilidad** (¿qué pasó?), de **auditoría** (¿quién lo hizo y cuándo?) y de **gobernanza multi-empresa** (¿mis datos están separados de los de otra empresa que usa el mismo sistema?).

## Cómo lo piensa resolver Swampert

Swampert ataca el problema modelando, de forma completa y ordenada, **todo el ciclo de vida de una tarea resuelta por un enjambre**:

1. **Aislamiento por empresa**: cada empresa cliente ve únicamente sus propios enjambres, agentes, ejecuciones y costos. Ninguna empresa puede ver ni accidentalmente los datos de otra, sin importar que compartan la misma plataforma.

2. **Trazabilidad paso a paso**: cada ejecución de una tarea queda registrada como una secuencia de pasos, de modo que se puede reconstruir exactamente qué razonó y qué hizo cada agente, en qué orden, y con qué herramientas.

3. **Control de costos**: cada ejecución lleva asociado el costo en tokens que insumió, lo que permite a una empresa entender cuánto le cuesta usar IA para resolver cada tipo de tarea, y detectar desvíos.

4. **Registro de errores**: cuando algo falla, queda un rastro claro de en qué paso ocurrió y por qué, en lugar de un enjambre que simplemente "no funcionó" sin más explicación.

5. **Auditoría de acciones humanas**: además de auditar a los agentes, Swampert también registra qué usuarios humanos hicieron cambios sobre la configuración del sistema (crear un agente, modificar un enjambre, etc.), para tener responsabilidad clara de ambos lados.

6. **Un panel para ver todo esto de un vistazo**: toda esta información solo es útil si se puede consultar de forma simple. Swampert incluye un dashboard donde se puede filtrar y explorar esta información (por empresa, por fecha, por tarea, por agente) sin necesidad de escribir consultas a mano.

## Lo que Swampert *no* resuelve (a propósito)

Es importante ser honestos sobre el alcance: Swampert **no ejecuta agentes de IA reales ni hace llamadas a modelos de lenguaje**. Su enfoque está puesto exclusivamente en **modelar y auditar** cómo se vería ese ecosistema de agentes desde el punto de vista de los datos: quién hizo qué, cuánto costó, y quién puede verlo. Todo lo relacionado con la ejecución real de los agentes queda deliberadamente fuera de este proyecto.