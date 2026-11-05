# Preparación para calibración física

La etapa de preparación original fue ampliada con calibración geométrica. La guía vigente es [PROJECTOR_GUIDE.md](PROJECTOR_GUIDE.md); la primera prueba física sigue pendiente. El flujo CAMERA anterior permanece desacoplado:

`cámara → detector/seguimiento → coordenadas normalizadas → UDP v1 → PlatformManager → objetivos físicos`.

Antes de calibrar:

1. Fijar cámara y mesa; seleccionar índice/backend/resolución y medir `capture.measured_capture_hz`, `capture_read_timing` y `opencv_timing` durante al menos varios segundos tras la apertura. No confundir FPS configurados con medidos.
2. Ajustar HSV con las piezas físicas, iluminación y fondo definitivos. Guardar con S. Registrar `vision/config.json` junto con los reportes; para comparar ensayos no cambiar exposición, balance de blancos, resolución o espejo entre ellos.
3. Verificar ID 1 = verde/left e ID 2 = azul/right, centros y orientación de eje. Sólo una pieza por color; para dirección única 360° se necesita identificación adicional, por ejemplo un adaptador ArUco futuro.
4. Confirmar la convención actual: x/y de 0 a 1 respecto de toda la imagen, y hacia abajo, grados horarios. Godot los convierte al rectángulo `(150,180,980,340)`. Las geometrías continúan predefinidas en Godot.
5. Registrar oclusión, pérdida de cámara, cierre y reinicio del emisor. Comparar edad de observación por módulo en Python con edad de recepción por módulo en Godot: son medidas diferentes.
6. Medir correspondencias cámara/pared/proyector con el patrón de ocho referencias de la nueva escena. El transformador PROJECTOR actúa antes de emitir x/y normalizados; UDP v2 identifica explícitamente ese espacio. El combate y las plataformas no conocen OpenCV ni calculan la homografía.

El nuevo modo PROJECTOR transforma el centro y el eje de orientación, no solo x/y: perspectiva o espejo pueden cambiar el ángulo. CAMERA conserva el comportamiento anterior. Los archivos físicos de calibración son independientes de HSV y se validan antes de guardar/cargar.

Los campos opcionales de tiempo de UDP son diagnósticos locales. `sent_unix_ms` permite detectar datagramas viejos en el mismo equipo; no es un reloj de exposición de cámara. `source_age_ms` empieza cuando `VideoCapture.read()` devuelve un frame, no cuando se expusieron los píxeles. No representan latencia fotón-a-pantalla. Los plazos internos, el watchdog, el seguimiento y las métricas de rendimiento usan relojes monotónicos.

La configuración actual mantiene loopback IPv4. Una futura distribución en varias computadoras necesitará acordar sincronización de relojes o cambiar la medición de transporte; no usar los tiempos Unix actuales como latencia precisa entre equipos.
