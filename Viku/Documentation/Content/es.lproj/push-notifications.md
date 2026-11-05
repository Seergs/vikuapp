# Notificaciones push

Vikunja no envía notificaciones push a iOS por su cuenta: Apple solo proporciona esas credenciales a los desarrolladores de la propia app. Por eso, cuando activas las notificaciones en Viku, interviene un servicio intermediario: Viku Relay, que administramos los desarrolladores de Viku y que conecta tu instancia de Vikunja con tu iPhone.

Aquí explicamos cómo encajan las piezas y qué conviene saber sobre su funcionamiento.

## Cómo funciona

Vikunja ya tiene una función llamada webhooks: puedes indicarle «cuando suceda X, envía un mensaje a esta URL». Al activar las notificaciones en Viku, la app configura algunos de esos webhooks para que apunten a Viku Relay. Cuando Vikunja envía uno, el servicio lo convierte en una notificación push y la entrega a tu teléfono mediante el servicio de notificaciones de Apple.

No se configura nada en tu instancia hasta que activas las notificaciones. Antes de eso, Viku Relay no sabe que existes.

## Cómo activarlas

Ve a **Ajustes → Notificaciones**. Verás una breve explicación de lo que va a suceder y tendrás que confirmarla antes de que se cree nada. Después, iOS te pedirá permiso para mostrar notificaciones, como con cualquier otra app.

Puedes activar dos tipos de notificaciones independientes:

- **Tus eventos.** Cosas que te afectan personalmente, sin importar a qué proyecto pertenezcan, como un recordatorio de tarea o una tarea que vence. Reflejan los avisos que mostraría la campana de notificaciones de la web de Vikunja.
- **Eventos de cada proyecto.** Abre un proyecto y elige qué quieres recibir: tareas nuevas, tareas que te asignan, comentarios y otros eventos. No hay nada seleccionado de forma predeterminada; tú decides proyecto por proyecto.

Independientemente de lo que actives, no recibirás notificaciones por tus propias acciones. Comentar una tarea no genera una notificación para decirte que acabas de comentarla.

Si usas más de una cuenta de Vikunja en Viku, las notificaciones funcionan para todas las cuentas en las que las hayas activado, no solo para la que tengas abierta en ese momento. Así puedes enterarte de lo que sucede aunque no estés mirando esa cuenta.

## Cómo desactivarlas

Lo que realmente controla la función es el interruptor de **Ajustes → Notificaciones** de Viku. Al desactivarlo, se eliminan los webhooks que Viku creó en tu instancia de Vikunja y se cancela el registro de tu dispositivo en Viku Relay. No queda nada en ninguno de los dos lados.

### «Eliminé el webhook desde los ajustes de Vikunja, ¿por qué sigo recibiendo notificaciones?»

Estos webhooks son webhooks normales, por lo que puedes verlos en los ajustes de Vikunja como cualquier otro. Sin embargo, eliminar uno desde ahí no avisa a Viku. Para la app, el interruptor sigue activado.

La próxima vez que Viku compruebe la configuración, al abrir la pantalla de Notificaciones o al abrir la app, detectará que falta el webhook esperado y lo volverá a crear automáticamente. Desde tu perspectiva, parecerá que nada ha cambiado: las notificaciones seguirán llegando.

Para dejar de recibirlas, utiliza el interruptor de Viku. Eliminar el webhook únicamente desde Vikunja no basta; Viku volverá a crearlo.

## Dos limitaciones que conviene conocer

**Puede quedar un webhook inactivo en tu instancia de Vikunja si tu sesión ya había vencido cuando desactivaste las notificaciones o eliminaste esa conexión.**

Desactivar todo correctamente requiere dos pasos: cancelar el registro en el servicio intermediario, algo que Viku siempre puede hacer, y eliminar el webhook de tu servidor Vikunja, lo que requiere una sesión válida en ese servidor. Si la sesión ya había vencido, Viku puede impedir que las notificaciones lleguen a tu teléfono, pero no puede volver a iniciar sesión por ti para eliminar ese webhook. El webhook permanece configurado y apunta a un servicio que rechazará lo que envíe. Está inactivo y no supone un problema de privacidad; si quieres eliminarlo, puedes hacerlo manualmente desde los ajustes de webhooks de Vikunja.

**Si tienes varias cuentas de Vikunja en el mismo teléfono, sus notificaciones pueden recuperarse en momentos distintos después de una reinstalación.**

Reinstalar la app o restaurar el teléfono desde una copia de seguridad cambia el token que Apple utiliza para localizar tu dispositivo. El servicio intermediario no lo descubre hasta que intenta enviar una notificación a una cuenta afectada; entonces elimina el registro de esa cuenta. Las demás cuentas del dispositivo no se ven afectadas hasta que cada una tiene su propio evento que entregar. En la práctica, una cuenta que usas a diario se recupera casi de inmediato, mientras que otra menos activa puede tardar hasta que ocurra algo en ella.

## Qué información ve el servicio intermediario

La necesaria para crear la notificación: el tipo de evento, el título de la tarea y el nombre del proyecto. Tu contraseña o token de acceso de Vikunja nunca sale de tu dispositivo y el servicio no conserva un registro de las notificaciones que entrega. La pantalla de consentimiento incluye un enlace a su política de privacidad, donde puedes consultar qué se almacena y durante cuánto tiempo.

## Qué más conviene saber

- Tu instancia de Vikunja no necesita ser accesible desde internet. Puede estar en un servidor doméstico o en una red privada sin acceso entrante. Sí necesita acceso saliente a Viku Relay mediante HTTPS, porque es tu instancia la que envía la solicitud del webhook.
- Esta función es opcional. Si nunca la activas, nada más cambia en tu forma de usar Viku.
