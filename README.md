# BikeWatch

> App de iPhone y Apple Watch para entrenar en bici estática con cualquier sensor Bluetooth estándar.

El iPhone se conecta a la bici por Bluetooth Low Energy, muestra cadencia, potencia y velocidad en tiempo real y guarda cada sesión. El Apple Watch lleva la sesión de entrenamiento de HealthKit (pulso y calorías) y la guarda en la app Salud. Los dos dispositivos se sincronizan durante el entrenamiento.

## Funcionalidades

**iPhone**
- Conexión BLE con perfil **FTMS** (*Indoor Bike Data*) y alternativa **Cycling Power**.
- Métricas en directo: cadencia, potencia y velocidad.
- Avisos por voz con parciales (entrenador).
- Historial de entrenamientos con gráficas (Swift Charts).
- **Actividad en directo** en la pantalla de bloqueo y la Dynamic Island.

**Apple Watch**
- Sesión de entrenamiento de HealthKit con pulso y calorías.
- Recibe los datos de la bici desde el iPhone en tiempo real.
- Guarda el entrenamiento en Salud.
- Atajos con App Intents.

## Stack

| Área | Tecnología |
|---|---|
| UI | SwiftUI, Observation |
| Sensores | CoreBluetooth (FTMS, Cycling Power) |
| Salud | HealthKit, sesión de entrenamiento espejada (`sendToRemoteWorkoutSession`) |
| Sistema | ActivityKit + WidgetKit, App Intents, AVFoundation (voz), Charts |
| Proyecto | XcodeGen (`project.yml`) |

## Arquitectura

```
Bici (BLE) ──► iPhone: BikeSensor ──► PhoneModel ──► Vistas / Coach (voz) / Actividad en directo
                                          │
                     HealthKit (sesión espejada)
                                          ▼
                     Watch: WorkoutManager ──► Salud
```

| Carpeta | Contenido |
|---|---|
| `Sources/Phone` | App de iPhone: sensor Bluetooth, modelo, voz y pantallas |
| `Sources/Watch` | App del reloj: sesión de entrenamiento y atajos |
| `Sources/Live` | Extensión de Actividad en directo |
| `Sources/LiveShared` | Atributos compartidos entre la app y la extensión |
| `Sources/Shared` | Código común a iPhone y reloj |

## Requisitos

- Xcode 26 o superior, iOS 26 y watchOS 26.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- Una bici o sensor que anuncie un nombre que empiece por `SPORT01`. El prefijo se cambia en `Sources/Phone/BikeSensor.swift`.

## Puesta en marcha

1. Pon tu Team ID de Apple en `DEVELOPMENT_TEAM` (`project.yml`) y, si quieres, cambia `bundleIdPrefix`.
2. Genera y abre el proyecto:

```bash
xcodegen
open BikeWatch.xcodeproj
```

Para instalar en iPhone y reloj desde la terminal:

```bash
IPHONE=<id-iphone> WATCH=<id-reloj> ./install.sh   # ids: xcrun devicectl list devices
```

El script instala la app del reloj directamente desde el Mac: con iOS 27 y watchOS 26.x la instalación desde el iPhone no llega a terminar. Con una cuenta gratuita de Apple la firma caduca a los 7 días.

## Hoja de ruta

- [ ] Planes de entrenamiento por intervalos
- [ ] Exportación a FIT/TCX
- [ ] Control de resistencia (FTMS Control Point)

## Licencia

[MIT](LICENSE)
