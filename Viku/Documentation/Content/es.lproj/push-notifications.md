---
title: Notificaciones push
summary: Elige qué avisos quieres recibir de tus tareas y proyectos.
category: setup
updated: 2026-11-06
related: server-version-support
---

# Notificaciones push

Recibe recordatorios y novedades de Vikunja en tu iPhone. Las notificaciones son opcionales y tú eliges qué recibir.

## Activa las notificaciones

1. Abre **Ajustes → Notificaciones**.
2. Lee y confirma la explicación, y permite las notificaciones cuando iOS lo solicite.
3. Activa tus eventos personales. Para recibir novedades de un proyecto, ábrelo y elige los eventos que te interesan.

Los eventos personales incluyen recordatorios y tareas vencidas. Los eventos de proyecto incluyen tareas nuevas, asignaciones y comentarios. Ningún evento de proyecto está seleccionado de forma predeterminada.

No recibirás avisos por tus propias acciones. Si activas las notificaciones en varias cuentas, podrás recibir novedades de todas, aunque tengas otra cuenta abierta.

## Tu privacidad

Las notificaciones utilizan **Viku Relay**, un servicio administrado por los desarrolladores de Viku. Recibe la información necesaria para crear cada aviso, incluidos el tipo de evento, el título de la tarea y el nombre del proyecto. Viku no comparte tu contraseña ni tu token de acceso de Vikunja con Relay, y Relay no guarda un registro de los avisos que entrega.

Puedes consultar la política de privacidad completa en la pantalla de consentimiento antes de activarlas. Tu servidor necesita una conexión saliente a Relay mediante HTTPS; no necesita ser accesible desde internet.

## Desactiva las notificaciones

Utiliza el interruptor de **Ajustes → Notificaciones** de Viku. Eliminar un webhook desde los ajustes de Vikunja no desactiva esta función: Viku puede volver a crearlo mientras las notificaciones sigan activadas.
