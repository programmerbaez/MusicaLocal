# Música Local — instalador DMG con fondo generado en Swift

## Cómo instalar

Coloca `build-dmg.sh` y `DMGBackground.swift` en la **raíz del proyecto**.

La app compilada debe estar en:

```text
release/.app/MusicaLocal.app
```

Ejecuta:

```bash
chmod +x build-dmg.sh
./build-dmg.sh
open dist/MusicaLocal-1.0.dmg
```

No utiliza Homebrew ni `create-dmg`. Requiere las herramientas de compilación Swift ya utilizadas por el proyecto.

## Diseño adaptable

El archivo `DMGBackground.swift` dibuja un fondo nuevo en cada compilación con AppKit: marfil, palmas vectoriales y títulos. No depende de un PNG preparado previamente. En `build-dmg.sh` puedes cambiar `WINDOW_WIDTH` y `BACKGROUND_HEIGHT`; el generador actualiza las dimensiones del fondo y las posiciones de los iconos proporcionalmente.

**Limitación de Finder:** los fondos DMG no pueden ser vistas Swift interactivas ni cambiar de tamaño en tiempo real. El script genera un recurso PNG específico para la ventana de Finder. El resultado evita deformaciones por imágenes de tamaño incorrecto, pero si redimensionas manualmente la ventana posteriormente, el fondo no se reacomodará dinámicamente. Los detalles de alta densidad siguen condicionados por el modo en que Finder representa la imagen de fondo.

## Distribución

Sube `dist/MusicaLocal-1.0.dmg` como recurso adjunto de la versión `v1.0.0` en GitHub Releases. No incluyas `MusicaLocal.app` ni el DMG compilado en el código fuente del repositorio.
