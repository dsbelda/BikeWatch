#!/bin/zsh
# Compila e instala BikeWatch en iPhone y reloj, en este orden.
# El iPhone va primero: al reinstalarlo, el sistema borra la app acompañante del reloj.
# El reloj se instala desde el Mac porque la instalación desde el iPhone falla (iOS 27 + watchOS 26.x).
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=${IPHONE:?Define IPHONE con el identificador de tu iPhone (xcrun devicectl list devices)}
WATCH=${WATCH:?Define WATCH con el identificador de tu reloj}

xcodegen
for s in BikePhone BikeWatch; do
  xcodebuild -project BikeWatch.xcodeproj -scheme $s -configuration Release \
    -destination "generic/platform=$([ $s = BikePhone ] && echo iOS || echo watchOS)" \
    -allowProvisioningUpdates -derivedDataPath build build | grep -E "error:|BUILD"
done
xcrun devicectl device install app --device $IPHONE build/Build/Products/Release-iphoneos/BikePhone.app
# La conexión con el reloj a veces tarda: hasta 3 intentos.
for i in 1 2 3; do
  xcrun devicectl device install app --device $WATCH build/Build/Products/Release-watchos/BikeWatch.app && break
  echo "Reintentando reloj ($i)…"; sleep 20
done
