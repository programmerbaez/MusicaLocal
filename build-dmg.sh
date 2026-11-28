#!/usr/bin/env bash
# DMG Música Local — fondo Retina (1x + 2x) generado desde Swift, sin Homebrew.
# Pensado para macOS 12 (Monterey).
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP="$ROOT/release/app/MusicaLocal.app"
SWIFT_SRC="$ROOT/DMGBackground.swift"

# ── Geometría (todo en PUNTOS, no en píxeles) ───────────────────────────────
WINDOW_WIDTH=760        # ancho del área de contenido = ancho del fondo
CONTENT_HEIGHT=450      # alto del área de contenido = alto del fondo
# Finder cuenta la barra de título dentro de "bounds". En macOS 11/12, con la
# barra de herramientas oculta, mide 28 pt. Si ves una franja vacía abajo o el
# fondo recortado, ajusta este valor (p. ej. 22 o 30).
TITLEBAR_HEIGHT=28
WINDOW_X=140
WINDOW_Y=120
ICON_SIZE=112
ICON_Y_PERCENT=56       # altura de los iconos como % del alto del fondo
# ────────────────────────────────────────────────────────────────────────────

WINDOW_HEIGHT=$((CONTENT_HEIGHT + TITLEBAR_HEIGHT))
APP_ICON_X=$((WINDOW_WIDTH * 25 / 100))
LINK_ICON_X=$((WINDOW_WIDTH * 75 / 100))
ICON_Y=$((CONTENT_HEIGHT * ICON_Y_PERCENT / 100))

[[ "$(uname -s)" == Darwin ]] || { echo 'ERROR: Este script requiere macOS.'; exit 1; }
[[ -d "$APP" ]] || { echo "ERROR: No existe $APP. Ejecuta ./build.sh"; exit 1; }
[[ -f "$SWIFT_SRC" ]] || { echo "ERROR: Falta $SWIFT_SRC"; exit 1; }
for c in swiftc hdiutil osascript ditto tiffutil sips; do
  command -v "$c" >/dev/null || { echo "ERROR: No se encontró $c"; exit 1; }
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo 'ERROR: Versión inválida en la aplicación.'; exit 1; }
OUT="$ROOT/dist/MusicaLocal-$VERSION.dmg"
VOLUME="Música Local $VERSION"

mkdir -p "$ROOT/dist"
TMP="$(mktemp -d "${TMPDIR:-/tmp/}musicalocal-dmg.XXXXXXXX")"
RAW="$TMP/installer-rw.dmg"
STAGE="$TMP/stage"
mkdir -p "$STAGE/.background"
DEVICE=""
MOUNT=""

detach_volume() {
  local target="$1" i
  for i in 1 2 3 4 5; do
    hdiutil detach "$target" -quiet 2>/dev/null && return 0
    sleep 1
  done
  hdiutil detach "$target" -force -quiet 2>/dev/null || true
}

cleanup() {
  if [[ -n "$DEVICE" ]]; then detach_volume "$DEVICE"; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

# ── 1. Fondo @1x y @2x → un único TIFF multirresolución ─────────────────────
echo '[1/6] Dibujando fondo (1x y 2x) con Swift/AppKit...'
swiftc -O "$SWIFT_SRC" -o "$TMP/DMGBackground"
"$TMP/DMGBackground" "$WINDOW_WIDTH" "$CONTENT_HEIGHT" "$TMP/bg.png"    1 "$VERSION"
"$TMP/DMGBackground" "$WINDOW_WIDTH" "$CONTENT_HEIGHT" "$TMP/bg@2x.png" 2 "$VERSION"

# Finder elige solo la representación correcta (1x o 2x) según la pantalla.
# Con un PNG único de 760x450 a 72 dpi, en Retina se ampliaba x2 → borroso.
BACKGROUND_NAME="background.tiff"
if tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" \
     -out "$STAGE/.background/$BACKGROUND_NAME" 2>/dev/null; then
  echo "      Fondo multirresolución OK ($(sips -g pixelWidth "$TMP/bg@2x.png" | awk '/pixelWidth/{print $2}') px de ancho en @2x)."
else
  echo '      AVISO: tiffutil falló; se usa PNG @2x a 144 dpi como alternativa.'
  BACKGROUND_NAME="background.png"
  cp "$TMP/bg@2x.png" "$STAGE/.background/$BACKGROUND_NAME"
fi

# ── 2. Contenido del volumen ─────────────────────────────────────────────────
echo '[2/6] Preparando instalador...'
ditto "$APP" "$STAGE/MusicaLocal.app"
ln -s /Applications "$STAGE/Aplicaciones"

SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -srcfolder "$STAGE" -fs HFS+ -volname "$VOLUME" \
  -size "${SIZE_MB}m" -format UDRW -ov "$RAW" >/dev/null

# ── 3. Montaje en /Volumes ───────────────────────────────────────────────────
# Importante: debe montarse en /Volumes (sin -nobrowse ni -mountpoint). Finder
# guarda en .DS_Store un alias al fondo; si el volumen estaba en una ruta
# temporal, ese alias puede fallar o verse distinto al abrir el DMG final.
echo '[3/6] Montando volumen...'
if [[ -d "/Volumes/$VOLUME" ]]; then
  echo "      Desmontando una copia anterior de /Volumes/$VOLUME..."
  detach_volume "/Volumes/$VOLUME"
fi
ATTACH_OUT="$(hdiutil attach "$RAW" -readwrite -noverify -noautoopen)"
DEVICE="$(printf '%s\n' "$ATTACH_OUT" | awk '/^\/dev\//{print $1; exit}')"
MOUNT="$(printf '%s\n' "$ATTACH_OUT" | sed -n 's|^/dev/[^[:space:]]*[[:space:]]*Apple_HFS[[:space:]]*||p' | head -n 1)"
[[ -n "$DEVICE" && -d "$MOUNT" ]] || { echo 'ERROR: No se pudo determinar el punto de montaje.'; exit 1; }
echo "      Montado en: $MOUNT"

# ── 4. Aspecto de la ventana de Finder ───────────────────────────────────────
echo '[4/6] Ajustando Finder...'
osascript - "$MOUNT" "$WINDOW_X" "$WINDOW_Y" "$WINDOW_WIDTH" "$WINDOW_HEIGHT" \
  "$ICON_SIZE" "$APP_ICON_X" "$LINK_ICON_X" "$ICON_Y" "$BACKGROUND_NAME" <<'APPLESCRIPT'
on run argv
    set mountPath to item 1 of argv
    set x0 to (item 2 of argv) as integer
    set y0 to (item 3 of argv) as integer
    set w to (item 4 of argv) as integer
    set winH to (item 5 of argv) as integer
    set iconSz to (item 6 of argv) as integer
    set appX to (item 7 of argv) as integer
    set linkX to (item 8 of argv) as integer
    set iconY to (item 9 of argv) as integer
    set bgName to item 10 of argv

    tell application "Finder"
        activate
        set diskFolder to (POSIX file mountPath) as alias
        open diskFolder
        delay 1
        set theWindow to container window of folder diskFolder
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set bounds of theWindow to {x0, y0, x0 + w, y0 + winH}

        set viewOptions to icon view options of theWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to iconSz
        set text size of viewOptions to 12
        set background picture of viewOptions to ((POSIX file (mountPath & "/.background/" & bgName)) as alias)

        set position of item "MusicaLocal.app" of theWindow to {appX, iconY}
        set position of item "Aplicaciones" of theWindow to {linkX, iconY}

        -- Finder a veces ignora los bounds hasta que cambia la vista: se repiten.
        delay 1
        set bounds of theWindow to {x0, y0, x0 + w, y0 + winH}
        update diskFolder without registering applications
        delay 2
        close theWindow
    end tell
end run
APPLESCRIPT

# ── 5. Esperar a que Finder escriba .DS_Store y desmontar ────────────────────
echo '[5/6] Guardando ajustes y desmontando...'
for _ in $(seq 1 20); do
  [[ -f "$MOUNT/.DS_Store" ]] && break
  sleep 0.5
done
[[ -f "$MOUNT/.DS_Store" ]] || echo '      AVISO: no apareció .DS_Store; el diseño podría no guardarse.'
sync
sleep 1
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
detach_volume "$DEVICE"
DEVICE=""

# ── 6. Imagen final comprimida ───────────────────────────────────────────────
echo '[6/6] Comprimiendo imagen final...'
FINAL="$TMP/MusicaLocal-$VERSION.dmg"
hdiutil convert "$RAW" -format UDZO -imagekey zlib-level=9 -o "$FINAL" >/dev/null
mv -f "$FINAL" "$OUT"
echo "Instalador generado: $OUT"
echo "Prueba: open \"$OUT\""
