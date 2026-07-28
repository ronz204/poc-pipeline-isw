# Swampert — Vista General

## ¿Qué es Swampert?

Swampert es una plataforma que **orquesta y audita enjambres de agentes de IA**. Imaginate una empresa que en vez de tener un solo asistente de IA, tiene equipos enteros de agentes trabajando en paralelo, cada uno con su rol, sus herramientas y su propio historial de decisiones. Swampert es el sistema que lleva el registro de todo eso: qué agente hizo qué, cuánto costó en tokens, en qué paso falló, y quién puede ver qué información dentro de la empresa.

Pensalo como una mezcla entre un **panel de control** y un **libro contable** para agentes de IA: no ejecuta los agentes en sí (eso queda fuera del alcance del proyecto), pero sí modela con total fidelidad cómo se vería el sistema que los supervisa, les hace seguimiento y les rinde cuentas a los humanos responsables.

## ¿De qué se trata el proyecto?

Swampert es un **producto multi-tenant**, es decir, está pensado para que múltiples empresas clientes lo usen al mismo tiempo, cada una viendo únicamente sus propios datos, sin mezclarse con los de otras. Cada empresa puede tener:

- **Enjambres** (swarms): grupos de agentes que colaboran para resolver una tarea.
- **Agentes**: unidades individuales dentro de un enjambre, cada una con su configuración y sus herramientas asignadas.
- **Tareas**: el trabajo concreto que se le pide resolver a un enjambre.
- **Ejecuciones**: cada intento de resolver una tarea (puede haber reintentos).
- **Pasos de ejecución**: el detalle paso a paso de lo que un agente pensó e hizo dentro de una ejecución.
- **Costos de tokens**: cuánto "costó" en tokens cada ejecución, para poder controlar gastos.
- **Errores** y **logs de auditoría**: todo lo que salió mal y quién hizo qué, para poder investigar después.

La idea nace inspirada en herramientas reales de observabilidad de agentes de IA que ya existen en la industria (como LangSmith o Langfuse), pero llevada a una escala más simple y didáctica.
