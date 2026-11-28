# Privacidad — Música Local

**Versión:** 1.0 · **24 de noviembre de 2026**  
**Responsable del proyecto:** Andrés Báez

## Datos utilizados

Música Local accede a las carpetas que el usuario selecciona para localizar archivos de audio y leer metadatos. Conserva localmente información de biblioteca (`library.json`), preferencias (`settings.json`) y miniaturas de carátulas en el directorio de soporte de la aplicación.

## Tratamiento y almacenamiento

La reproducción y la configuración están diseñadas para funcionar localmente, sin cuentas de usuario ni conexión obligatoria a Internet. La aplicación no incorpora, en esta versión del proyecto, un servicio propio de analítica, publicidad o recopilación remota de los datos de la biblioteca. La comunicación que realice macOS, o las funciones integradas con el sistema, se rige además por las políticas de Apple.

## Control del usuario

Puedes seleccionar o cambiar la carpeta de música desde **Configuración → Caché**, desactivar el almacenamiento de caché y eliminar la caché desde la aplicación. Las preferencias persistentes se guardan por separado y pueden requerir eliminación manual si deseas restablecer todos los ajustes.

## Identificación acústica opcional

Al pulsar **Identificar canción**, la aplicación lee localmente parte del archivo seleccionado para calcular una huella. Envía únicamente la huella, la duración, la clave de aplicación y, si se introduce, la clave de usuario a AcoustID. No graba el micrófono ni el audio del sistema y no envía el archivo musical. Al seleccionar una grabación o edición, MusicBrainz y Cover Art Archive reciben los identificadores pertinentes para devolver etiquetas y portada. Los servicios reciben la información normal de una conexión a Internet, como la dirección IP. La clave de usuario permanece en memoria durante la operación y se descarta al cerrar el editor. [AcoustID](https://acoustid.org/webservice) · [Privacidad de MetaBrainz](https://metabrainz.org/privacy)

Al aplicar cambios, se crea una copia de recuperación local junto al archivo musical. El resto de la biblioteca queda fuera de la operación.

## Archivos musicales y derechos

Los archivos de música y sus metadatos pertenecen a sus respectivos titulares. El programa no transfiere derechos sobre esos contenidos.

## Cambios

La política puede actualizarse cuando se incorporen funciones de red, sincronización o telemetría. Esas funciones requerirían explicar su tratamiento de datos antes de introducirlas.
