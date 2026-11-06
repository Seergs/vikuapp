---
title: Atajos de creación rápida
summary: Asigna fechas, proyectos, etiquetas y prioridades mientras escribes.
category: basics
updated: 2026-11-05
related: offline-mode
---

# Atajos de creación rápida

La pantalla de creación rápida reconoce atajos escritos directamente en el título,
para que puedas asignar un proyecto, una prioridad o etiquetas sin abrir sus
selectores. La función es experimental y está desactivada de forma predeterminada.
Para activarla, ve a **Ajustes → Experimental → Creación rápida** y elige una sintaxis:

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
- Un nombre de proyecto o etiqueta que coincide con varios elementos, o un proyecto que no coincide con ninguno, permanece en el título y muestra un indicador para que sepas qué sucederá al guardar. Selecciona el proyecto o la prioridad en los campos de la pantalla y el atajo correspondiente se escribirá en el título.

Mientras los atajos estén desactivados, el título se guarda tal como lo escribiste,
eliminando únicamente los espacios al inicio y al final.

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
título, Guardar se desactiva.

Todavía no se puede descartar una fecha reconocida. Para conservar esa expresión
literalmente en el título, desactiva Quick Add Magic o edita la tarea después de
crearla. El interruptor de vista previa de fechas en Desarrollador solo controla el
panel de diagnóstico; no controla si las fechas se aplican.
