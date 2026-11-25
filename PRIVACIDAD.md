# Privacidad — Música Local

**Versión:** 1.0 · **24 de noviembre de 2026**  
**Responsable del proyecto:** Andrés Báez

## Datos utilizados

Música Local accede a las carpetas que el usuario selecciona para localizar archivos de audio y leer metadatos. Conserva localmente información de biblioteca (`library.json`), preferencias (`settings.json`) y miniaturas de carátulas en el directorio de soporte de la aplicación.

## Tratamiento y almacenamiento

La reproducción y la configuración están diseñadas para funcionar localmente, sin cuentas de usuario ni conexión obligatoria a Internet. La aplicación no incorpora, en esta versión del proyecto, un servicio propio de analítica, publicidad o recopilación remota de los datos de la biblioteca. La comunicación que realice macOS, o las funciones integradas con el sistema, se rige además por las políticas de Apple.

## Control del usuario

Puedes seleccionar o cambiar la carpeta de música desde **Configuración → Caché**, desactivar el almacenamiento de caché y eliminar la caché desde la aplicación. Las preferencias persistentes se guardan por separado y pueden requerir eliminación manual si deseas restablecer todos los ajustes.

## Archivos musicales y derechos

Los archivos de música y sus metadatos pertenecen a sus respectivos titulares. El programa no transfiere derechos sobre esos contenidos.

## Cambios

La política puede actualizarse cuando se incorporen funciones de red, sincronización o telemetría. Esas funciones requerirían explicar su tratamiento de datos antes de introducirlas.
