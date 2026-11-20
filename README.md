# BikeWatch

> App de iPhone y Apple Watch para entrenar en bici estática con cualquier bici o sensor Bluetooth estándar.

El iPhone se conecta a la bici por Bluetooth Low Energy, muestra cadencia, potencia y velocidad en tiempo real y guarda cada sesión. El Apple Watch lleva la sesión de entrenamiento de HealthKit (pulso y calorías) y la guarda en la app Salud. Los dos dispositivos se sincronizan durante el entrenamiento.

## Funcionalidades

**iPhone**
- Compatible con los perfiles Bluetooth estándar: **FTMS** (bicis y rodillos inteligentes), **Cycling Power** (potenciómetros) y **Cycling Speed and Cadence** (sensores de cadencia).
- Sensor configurable en Ajustes: filtro por nombre, "olvidar y buscar otro" y potencia medida o estimada con la cadencia y el nivel de resistencia.
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
| Sensores | CoreBluetooth (FTMS, Cycling Power, Cycling Speed and Cadence) |
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
- Una bici o sensor Bluetooth con FTMS, Cycling Power o Cycling Speed and Cadence. Se conecta al primero que encuentra; en **Ajustes → Sensor** puedes filtrar por nombre o cambiar de sensor.

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
- [ ] Selector de sensor con lista de dispositivos cercanos

## Licencia

[MIT](LICENSE)
