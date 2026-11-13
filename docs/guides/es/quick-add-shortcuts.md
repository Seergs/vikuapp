---
title: Quick Add Magic
summary: Asigna fechas, proyectos, etiquetas y prioridades mientras escribes.
category: basics
updated: 2026-11-12
related: offline-mode
---

# Quick Add Magic

La pantalla de creación rápida reconoce atajos escritos directamente en el título,
para que puedas asignar un proyecto, una prioridad o etiquetas sin abrir sus
selectores. Los atajos están desactivados de forma predeterminada.
Para activarla, ve a **Ajustes → General → Quick Add Magic** y elige una sintaxis:

- **Vikunja** utiliza los mismos símbolos que la creación rápida de Vikunja.
- **Todoist** utiliza los símbolos que ya conocen los usuarios de Todoist.

| Atajo | Vikunja | Todoist | Efecto |
|---|---|---|---|
| Proyecto | `+Compras` | `#Compras` | Guarda la tarea en ese proyecto |
| Etiqueta | `*casa` | `@casa` | Agrega la etiqueta. Puedes usar varias. Si una etiqueta no existe, se crea al guardar |
| Prioridad | De `!1` a `!5` | De `p1` a `p4` | Establece la prioridad |

Por ejemplo, con la sintaxis de Vikunja, `Llamar al plomero +"Reparaciones de casa" *urgente !4`
guarda una tarea titulada «Llamar al plomero» en el proyecto «Reparaciones de casa»,
con la etiqueta «urgente» y prioridad 4.

Así funcionan los atajos:

- Usa comillas en nombres con espacios: `+"Reparaciones de casa"`.
- Un atajo solo se reconoce al inicio del título o después de un espacio; `a#b` se conserva como texto.
- Escribe una barra invertida antes de un símbolo para conservarlo literalmente: `\#hashtag`.
- Los nombres coinciden sin distinguir mayúsculas ni acentos; `+compras` encuentra «Compras».
- Los atajos aplicados se eliminan del título. Si repites un proyecto o una prioridad, solo se aplica el primero.
- Un nombre de proyecto o etiqueta que coincide con varios elementos, o un proyecto que no coincide con ninguno, permanece en el título; solo se resaltan los atajos resueltos. Selecciona el proyecto o la prioridad en los chips y el atajo correspondiente se escribirá en el título.

Mientras los atajos estén desactivados, el título se guarda tal como lo escribiste,
eliminando únicamente los espacios al inicio y al final.

## Selectores y selección del borrador

Los chips de proyecto, prioridad, fecha límite, etiquetas y recordatorio funcionan incluso con Magic desactivado. Toca un chip para editarlo y la flecha hacia arriba para crear la tarea. Puedes seleccionar varias etiquetas existentes; su chip muestra la primera y un contador de las demás. Todavía no se pueden crear etiquetas desde el selector; las etiquetas nuevas escritas como atajos conservan el comportamiento de guardado descrito arriba.

Cada chip seleccionado tiene una × para quitar su valor, excepto el proyecto. La × de etiquetas limpia todas las etiquetas seleccionadas y sus atajos aplicados. Elegir una fecha en el calendario reemplaza la expresión reconocida en el input; una nueva fecha reconocida escrita después vuelve a prevalecer. Las sugerencias solo aparecen con Magic activado y el título vacío, usando los símbolos de esa sintaxis.

La creación rápida admite un recordatorio, con fecha y hora específicas o relativo a la fecha límite. Cambiar la fecha límite recalcula el recordatorio relativo. Quitar una fecha vinculada, desde el selector o el input, pide quitar ambos; cancelar conserva la fecha, el recordatorio y el texto original. Quitar solo el recordatorio no pide confirmación y conserva la fecha límite. Los recordatorios de fecha específica son independientes de la fecha límite. Estas selecciones permanecen en el borrador hasta que la creación de la tarea se acepta localmente, también sin conexión.

## Fechas de vencimiento

Con cualquiera de las dos sintaxis activada, la creación rápida también reconoce
fechas en español e inglés, como `mañana`, `tomorrow`, `próximo sábado`,
`en tres días`, `in two months` y `2027-11-15`. Puedes agregar una hora con
`mañana a las 18:30` o `tomorrow at 6pm`.

Una única fecha válida aparece resaltada. Al guardar `Comprar leche mañana a las
6pm`, se crea «Comprar leche» con ese vencimiento. Si no escribes una hora,
se utiliza 23:59:59 en la zona horaria del dispositivo. Las fechas relativas usan
la referencia temporal y la zona del dispositivo capturadas al abrir la creación
rápida. La sincronización sin conexión conserva el instante resuelto, sin volver
a interpretar las palabras. Cambiar después la zona del dispositivo no mueve el
vencimiento guardado, aunque su hora local mostrada puede cambiar.

Las expresiones ambiguas, inválidas, incompletas o no compatibles permanecen en el
título y no asignan un vencimiento. Por ejemplo, `hoy o mañana` no elige ninguno de
los dos días. Si al quitar la fecha y los demás atajos aplicados no queda un
título, el botón de crear se desactiva.

Para conservar una expresión reconocida literalmente en el título, desactiva Quick Add Magic o edita la tarea después de
crearla. El interruptor de vista previa de fechas en Desarrollador solo controla el
panel de diagnóstico; no controla si las fechas se aplican.

## Busca con la misma sintaxis

La búsqueda comparte la configuración de Quick Add Magic y el reconocimiento de atajos. Con Magic desactivado, la consulta se busca literalmente en el título. Con Magic activado, `*Bug +Trabajo !3 login` (Vikunja) o `@Bug #Trabajo p2 login` (Todoist) combina texto del título con filtros de etiqueta, proyecto y prioridad. Las etiquetas se combinan con O; el texto, el proyecto y la prioridad se combinan con Y. Solo se aplica el primer atajo de proyecto y prioridad. Las fechas y los asignados no se interpretan como filtros.

Los nombres coinciden sin distinguir mayúsculas ni acentos. Si hay nombres duplicados, se incluyen todas las identidades coincidentes. Los nombres desconocidos se eliminan del texto y se ignoran como filtros, igual que en Vikunja web. Por ejemplo, `*Bgu login` busca «login» sin restringir por etiqueta si «Bgu» no existe localmente. `*Bug *Bgu login` sigue filtrando por «Bug» si esa etiqueta existe. Una consulta compuesta solo por nombres desconocidos muestra todas las tareas locales. El campo realmente vacío conserva la pantalla inicial. Los nombres entre comillas y los símbolos escapados siguen las reglas de Quick Add.

La búsqueda es local y de solo lectura: no crea etiquetas, no hace búsquedas remotas ni inicia sincronizaciones. Incluye asignaciones y retiradas de etiquetas pendientes e identidades locales sin ID del servidor. Los fallos de subida conservan las ediciones locales. Tras un conflicto, la búsqueda usa el estado guardado por el flujo de sincronización existente y mantiene la edición pendiente disponible para resolverla. Solo cubre datos guardados localmente; una descarga pendiente o fallida puede dejar resultados incompletos o desactualizados. No observa sincronizaciones ni ediciones externas; cambiar la consulta recalcula los resultados. El texto se busca como una subcadena del título sin distinguir mayúsculas, sin buscar en la descripción ni ordenar por relevancia.
