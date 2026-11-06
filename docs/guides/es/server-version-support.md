---
title: Compatibilidad del servidor
summary: Consulta qué versiones del servidor Vikunja son compatibles.
category: setup
updated: 2026-11-05
related: push-notifications, offline-mode
---

# Compatibilidad del servidor

Viku funciona con cualquier instancia de Vikunja. Detecta durante la ejecución qué funciones admite tu servidor, sin asumir una única estructura de API, y utiliza automáticamente la nueva API v2 de Vikunja cuando tu instancia la ofrece (2.4.0 o posterior). En caso contrario, utiliza v1. Este proceso es transparente y no necesitas hacer nada.

El plan de Vikunja para retirar la API v1 es el siguiente, según [su documentación](https://vikunja.io/docs/api-v2/). Las fechas son estimaciones del proyecto y pueden cambiar:

| | Versión de Vikunja | Fecha estimada |
|---|---|---|
| v1 congelada (solo correcciones de errores) | 2.4.0 | Publicada |
| v1 declarada obsoleta | 3.0 | Aproximadamente T3/T4 de 2026 |
| v1 eliminada | 4.0 | Aproximadamente el segundo semestre de 2027 |

**Nuestro plan:** Viku seguirá funcionando con instancias que solo ofrecen v1 mientras los propios servidores de Vikunja la admitan, sin que tengas que hacer nada. Cuando Vikunja elimine v1 en su versión 4.0, seguiremos admitiendo instancias con versiones anteriores durante unos seis meses más para darte tiempo de actualizar. Después, dejará de ser compatible el uso de Viku con servidores anteriores a Vikunja 2.4.0. Si puedes, mantener tu instancia en la versión 2.4.0 o posterior es la opción más segura a largo plazo.
