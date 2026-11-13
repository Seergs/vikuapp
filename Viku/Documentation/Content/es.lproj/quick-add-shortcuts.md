---
title: Quick Add Magic
summary: Añade una tarea, su proyecto y su fecha mientras escribes.
category: basics
updated: 2026-11-12
related: offline-mode
---

# Quick Add Magic

Captura y organiza una tarea en una sola línea, sin abrir cada campo por separado.

## Activa los atajos

Abre **Ajustes → General → Quick Add Magic** y elige **Vikunja** o **Todoist**, según cuál te resulte familiar. Los atajos están desactivados de forma predeterminada.

## Prueba con una tarea

Con **Vikunja**, escribe:

`Comprar leche mañana +Compras *casa`

Con **Todoist**, escribe:

`Comprar leche mañana #Compras @casa`

Ambos crean «Comprar leche» en tu proyecto existente «Compras», con la etiqueta «casa» y vencimiento mañana. Si la etiqueta no existe, se crea al guardar.

| Añadir | Vikunja | Todoist |
|---|---|---|
| Proyecto | `+Compras` | `#Compras` |
| Etiqueta | `*casa` | `@casa` |
| Prioridad | De `!1` a `!5` | De `p1` a `p4` |

Escribe entre comillas los nombres con espacios, como `+"Reparaciones de casa"`.

## Añade una fecha

Prueba con `mañana`, `próximo sábado` o `en tres días`. Las fechas en español e inglés funcionan con ambos estilos de atajos. Incluye una hora con `mañana a las 18:30`; sin hora, la tarea vence al final de ese día.

## Revisa antes de guardar

Comprueba la fecha resaltada y los indicadores de los atajos. El texto que no se reconoce o resulta ambiguo permanece en el título, así que revisa el proyecto y el vencimiento antes de guardar.

Para conservar una fecha reconocida como parte del título, desactiva los atajos antes de escribir la tarea o edita su título después de crearla.

## Busca con atajos

La búsqueda usa la misma configuración de Quick Add Magic. En modo Vikunja, `*Bug login` encuentra tareas cuyo título contiene «login» y que tienen la etiqueta «Bug». En modo Todoist, usa `@Bug login`. También puedes filtrar por proyecto y prioridad con los símbolos de la tabla. Las fechas y los asignados se conservan como texto de búsqueda.

Varias etiquetas coinciden con cualquiera de ellas. Los nombres duplicados incluyen todas las etiquetas o proyectos coincidentes. Los nombres de etiquetas y proyectos desconocidos se ignoran; una consulta que solo contiene atajos desconocidos muestra todas las tareas disponibles localmente. El campo vacío muestra la pantalla inicial. Antepon una barra inversa al símbolo de un atajo para buscarlo literalmente.

La búsqueda consulta datos descargados y cambios locales pendientes, incluso sin conexión. Los resultados pueden estar incompletos o desactualizados tras un fallo de sincronización. Se recalculan al cambiar la consulta; no se actualizan automáticamente mientras se sincronizan los datos. Con Magic desactivado, toda la consulta se busca como texto del título.
