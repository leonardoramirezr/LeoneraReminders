# LeoneraReminders

App de recordatorios para iOS hecha con SwiftUI que usa **AlarmKit** para que cada recordatorio suene como una alarma (aunque el teléfono esté en silencio o en un modo de concentración). No usa dependencias externas: sólo frameworks de Apple (SwiftUI, AlarmKit, AppIntents, Observation).

## Requisitos

- Xcode 26.1 o posterior (SDK de iOS 26.1).
- iPhone o iPad con iOS 26.0 o posterior.
- Abre `LeoneraReminders.xcodeproj`, elige tu equipo en *Signing & Capabilities* y ejecuta en un dispositivo.
  La primera vez la app pide permiso para programar alarmas (`NSAlarmKitUsageDescription` está en `Config/Info.plist`).

## Qué hace

- **Recordatorio** = título + fecha límite + repetición opcional.
- **Repeticiones** (basadas en las del CSV de Due): cada N horas, diario/cada N días, semanal en uno o varios días
  (incluye entre semana y fines de semana), mensual en un día o el último día del mes (cada N meses) y anual (cada N años).
  La regla guarda su propia hora y día, así que mover o posponer una ocurrencia no cambia la regla.
- **Posponer mueve la fecha límite**: «Recordar en 10 min» deja la fecha límite en ahora + 10 min (ya no hay una
  hora de "pospuesto hasta" aparte).
- **Al sonar** la alarma, ningún botón la completa (un toque rápido como «Detener» no debe marcarla por error):
  - **Detener** pospone el tiempo por defecto (10 min).
  - **Abrir app** pospone también y abre la app, donde se completa **deslizando** «Desliza para completar» o se
    elige otro tiempo de "Recordar en…" (1, 5, 10, 20, 40 y 60 min, 2 h y 3 h por defecto; se pueden quitar y agregar).
  - En la lista, tocar el círculo también abre esa hoja; deslizar la fila a la derecha completa directamente.
  - Desde iOS 26.1 el control Detener lo dibuja el sistema (no se puede cambiar su texto); la app sólo decide qué hace.
- **Si ignoras la alarma, vuelve a sonar**: cada recordatorio deja programadas alarmas extra cada minuto (hasta 10 veces,
  configurable en *Configuración → Si ignoras la alarma*). Como están programadas de antemano, suenan aunque la app
  no esté abierta; al completar o posponer se cancelan todas.
- **Al entrar a la app, ningún vencido se queda callado**: los vencidos (con o sin repetición) que no estén sonando
  vuelven a sonar al empezar el siguiente minuto, y desde ahí siguen las repeticiones. Siguen apareciendo en «Vencidos».
- **Sonido** (*Configuración → Sonido*): Predeterminado del sistema, Campana, Despertador, Ascendente, Marimba, Pulso o
  **Sin sonido**. Los tonos de iOS no están disponibles para otras apps, así que estos van incluidos en la app
  (`LeoneraReminders/Sounds`, sintetizados para el proyecto).
- **«Sonar aunque esté en silencio»**: encendido (por defecto) usa alarmas de AlarmKit, que siempre suenan aunque el
  iPhone esté en silencio o en Concentración. Apagado usa notificaciones locales, que respetan el silencio (sólo
  vibran); tienen los mismos botones, pero iOS sólo guarda 64 pendientes, así que se programan las más próximas.
- **Matriz de ajuste rápido** en el editor: la primera fila fija una hora (10:00, 14:00, 18:00, 21:00), la segunda suma
  (+10 min, +1 h, +1 día, +1 sem.) y la tercera resta. Todas las celdas se cambian en *Configuración*.
  Ahí también se elige desde dónde suman en un recordatorio **vencido** (*Sumar a un vencido*): **desde la fecha
  límite** (por defecto; aunque ya haya pasado) o **desde ahora** (como posponer, ignorando la fecha vencida).
- **Importar CSV** (menú ⋯ → *Importar CSV…*) con las columnas `"Recordatorio","Fecha límite","Repetir"` de Due.
  Muestra una vista previa con avisos, omite duplicados y puede pasar los repetitivos vencidos a su próxima fecha.
  También acepta encabezados en inglés, punto y coma como separador y archivos en UTF-8, UTF-16 o Windows-1252.

## Cómo funciona por dentro

- Cada recordatorio pendiente tiene **alarmas de fecha fija** (la principal y las de repetición) (`Alarm.Schedule.fixed`) en AlarmKit. Las repeticiones
  las calcula la app: al completar, el recordatorio avanza a la siguiente ocurrencia y se programa una alarma nueva.
  (Las repeticiones nativas de AlarmKit sólo cubren "semanal a tal hora".)
- Los botones de la alarma ejecutan `LiveActivityIntent`s (`SnoozeReminderIntent`, `SnoozeOptionsIntent`) dentro del proceso de la app, que actualiza el recordatorio y reprograma.
- `AlarmSyncService` compara los recordatorios con `AlarmManager.alarms` y cancela/programa lo necesario; también
  reprograma si cambian los botones o el tiempo de posponer. Si AlarmKit llega a su límite de alarmas, se programan
  primero las más cercanas.

```
LeoneraReminders/
  App/        Punto de entrada
  Core/       Modelo y lógica sin interfaz (repeticiones, CSV, matriz, configuración) — probado con `swift test`
  Alarms/     AlarmKit: sincronización, metadatos e intents de los botones
  Stores/     Persistencia (JSON en Application Support y UserDefaults)
  Views/      SwiftUI
Config/Info.plist
Tests/ReminderCoreTests/
```

## Pruebas

La lógica de `LeoneraReminders/Core` también es un paquete de Swift (`Package.swift`) que compila en macOS y Linux:

```sh
swift test
```

## Builds automáticos (.ipa)

`.github/workflows/build.yml` compila un `.ipa` en cada push y lo publica como release:

| Rama | Tag | Release |
|------|-----|---------|
| `main` | `0.x.0` (empieza en `0.1.0`; cada push sube el número del medio) | Estable, marcada como *Latest* |
| cualquier otra | `build-<N>-<commit>` (`N` = número de ejecución del workflow, `commit` = 7 caracteres del hash) | Pre-release, nunca *Latest* |

El `.ipa` sale **sin firmar** (no hay certificados en el repositorio): para instalarlo hay que firmarlo, por ejemplo con
Sideloadly, AltStore o tu propio certificado de desarrollador.
