#!/usr/bin/env bash
# Música Local — compilación modular sin proyecto de Xcode (macOS 12+).
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
APP_NAME="MusicaLocal.app"
OUTPUT_DIR="$ROOT/release/dmg"
OUTPUT_APP="$OUTPUT_DIR/$APP_NAME"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_FILE="$LOG_DIR/build-${STAMP}-$$.log"
HISTORY="$LOG_DIR/build-history.log"
TMP_DIR=""
PERCENT=0

# Un solo fichero histórico y un fichero individual por intento.
log() {
    local line="$1"
    printf '%s\n' "$line" | tee -a "$LOG_FILE" >> "$HISTORY"
    printf '%s\n' "$line"
}
step() {
    PERCENT="$1"
    log "[$(printf '%3d' "$PERCENT")%] $2"
}
cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then rm -rf -- "$TMP_DIR"; fi
}
failed() {
    local code=$?
    trap - ERR
    log "[ERROR] Falló la compilación (exit $code; etapa $PERCENT%)."
    log "[ERROR] Registro: $LOG_FILE"
    log "[ERROR] La versión anterior de $APP_NAME se mantiene intacta."
    exit "$code"
}
trap cleanup EXIT
trap failed ERR

log "============================================================"
log "Inicio: $(date '+%Y-%m-%d %H:%M:%S %z')"
log "Ruta: $ROOT"
log "Registro por ejecución: $LOG_FILE"
step 0 "Inicio de compilación"

if [[ "$(uname -s)" != "Darwin" ]]; then
    log '[ERROR] Se requiere macOS para compilar con AppKit y SwiftUI.'
    false
fi
command -v swiftc >/dev/null 2>&1 || { log '[ERROR] No se encontró swiftc. Instala las herramientas de línea de comandos: xcode-select --install'; false; }
command -v plutil >/dev/null 2>&1 || { log '[ERROR] Falta plutil en el sistema.'; false; }
ARCH="$(uname -m)"
case "$ARCH" in
    arm64|x86_64) ;;
    *) log "[ERROR] Arquitectura no compatible: $ARCH"; false ;;
esac
TARGET="${ARCH}-apple-macos12.0"
step 10 "Sistema y compilador detectados ($ARCH, $TARGET)"
log "Swift: $(swiftc -version | head -n 1)"

[[ -f "$ROOT/MusicaLocal.swift" && -d "$ROOT/src" ]] || { log '[ERROR] Faltan MusicaLocal.swift o src/.'; false; }
SOURCES=("$ROOT/MusicaLocal.swift")
while IFS= read -r -d '' file; do SOURCES+=("$file"); done < <(find "$ROOT/src" -type f -name '*.swift' -print0 | sort -z)
[[ "${#SOURCES[@]}" -gt 1 ]] || { log '[ERROR] No se encontraron módulos Swift dentro de src/.'; false; }
step 20 "Fuentes encontradas: ${#SOURCES[@]} archivos Swift"

# Se construye fuera de la aplicación publicada para no dañarla si swiftc falla.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/musicalocal-build.XXXXXXXX")"
STAGED_APP="$TMP_DIR/$APP_NAME"
BIN="$STAGED_APP/Contents/MacOS/MusicaLocal"
mkdir -p "$(dirname "$BIN")"
step 30 "Compilando y enlazando con swiftc (esta fase puede tardar)"
log "Comando: swiftc -parse-as-library -O -target $TARGET <${#SOURCES[@]} archivos> -o <app temporal>"
# El compilador no proporciona un porcentaje fiable: se conserva 30% hasta que termine.
# tee replica todos los diagnósticos tanto en consola como en los dos registros.
swiftc -parse-as-library -O -target "$TARGET" "${SOURCES[@]}" -o "$BIN" \
    2>&1 | tee -a "$LOG_FILE" "$HISTORY"
step 85 "Compilación y enlace completados"

cat > "$STAGED_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MusicaLocal</string>
  <key>CFBundleIdentifier</key><string>com.local.musicalocal</string>
  <key>CFBundleName</key><string>Música Local</string>
  <key>CFBundleDisplayName</key><string>Música Local</string>
  <!-- Icono nativo en el bundle: Launch Services / Dock / interfaz multimedia de macOS. -->
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>CFBundleDevelopmentRegion</key><string>es</string>
  <key>CFBundleLocalizations</key><array><string>es</string></array>
  <key>NSHumanReadableCopyright</key><string>© 2026 Andrés Báez. Software libre y gratuito bajo licencia MIT.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Recursos de idioma y documentación legal disponibles dentro de la app.
mkdir -p "$STAGED_APP/Contents/Resources/es.lproj"
cp "$ROOT/resources/es.lproj/InfoPlist.strings" "$STAGED_APP/Contents/Resources/es.lproj/InfoPlist.strings"
cp "$ROOT/resources/es.lproj/Localizable.strings" "$STAGED_APP/Contents/Resources/es.lproj/Localizable.strings"
for document in LICENSE.md TERMINOS_Y_CONDICIONES.md PRIVACIDAD.md; do
    [[ -s "$ROOT/$document" ]] || { log "[ERROR] Falta documento legal: $document"; false; }
    cp "$ROOT/$document" "$STAGED_APP/Contents/Resources/$document"
done
log "Localización española y documentos legales incorporados al paquete"

# Crear icono .icns con herramientas incluidas en macOS (sin proyecto Xcode).
ICON_PNG="$ROOT/assets/AppIcon.png"
if [[ ! -f "$ICON_PNG" ]]; then
    log '[ERROR] Falta assets/AppIcon.png; el icono es obligatorio.'
    false
fi
command -v sips >/dev/null 2>&1 || { log '[ERROR] No se encontró sips.'; false; }
command -v iconutil >/dev/null 2>&1 || { log '[ERROR] No se encontró iconutil.'; false; }
ICONSET="$TMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET" "$STAGED_APP/Contents/Resources"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -s format png -z "$double" "$double" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
# iconutil solo admite tamaños base 16, 32, 128, 256 y 512.
iconutil -c icns "$ICONSET" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
[[ -s "$STAGED_APP/Contents/Resources/AppIcon.icns" ]] || { log '[ERROR] No se pudo generar AppIcon.icns.'; false; }
# Conservamos el PNG para vistas de la aplicación que muestran su propio icono.
# El icono del sistema es el .icns declarado en Info.plist; no se cambia
# NSApp.applicationIconImage en tiempo de ejecución ni se crea NSTouchBar.
cp "$ICON_PNG" "$STAGED_APP/Contents/Resources/AppIcon.png"
[[ -s "$STAGED_APP/Contents/Resources/AppIcon.png" ]] || { log '[ERROR] No se pudo copiar AppIcon.png.'; false; }
log "Icono nativo AppIcon.icns registrado en Info.plist (sin Touch Bar personalizada)"
plutil -lint "$STAGED_APP/Contents/Info.plist" 2>&1 | tee -a "$LOG_FILE" "$HISTORY"
[[ -x "$BIN" ]] || { log '[ERROR] swiftc no produjo un ejecutable válido.'; false; }
# Igual que la versión 1.0.0 original: firma ad hoc del paquete completo.
# No crea ni configura controles de Touch Bar.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$STAGED_APP" 2>/dev/null || true
fi
step 95 "Aplicación preparada y plist validado"

# Publicar únicamente si se completó todo. Restaurar si falla el reemplazo.
OLD_APP="$TMP_DIR/old-$APP_NAME"
mkdir -p "$OUTPUT_DIR"
if [[ -e "$OUTPUT_APP" ]]; then mv "$OUTPUT_APP" "$OLD_APP"; fi
if ! mv "$STAGED_APP" "$OUTPUT_APP"; then
    if [[ -e "$OLD_APP" ]]; then mv "$OLD_APP" "$OUTPUT_APP"; fi
    log '[ERROR] No se pudo publicar la aplicación; se restauró la versión previa.'
    false
fi
step 100 "Compilación finalizada correctamente"
log "Salida: $OUTPUT_APP"
log "Abrir: open \"$OUTPUT_APP\""
log "Registro: $LOG_FILE"
log "Fin: $(date '+%Y-%m-%d %H:%M:%S %z')"
log "============================================================"
