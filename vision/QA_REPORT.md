# Visión por colores — implementación y QA

Fecha: 30/10/2026. Python 3.14.5, OpenCV 5.0.0, NumPy 2.5.3, HighGUI WIN32. Juego inspeccionado y ejecutado mediante Godot AI MCP: Godot 4.6.3 oficial, sesión `juegofrei@fbd1`.

## Resultado funcional

El nuevo detector reemplaza el script antiguo de verde único y protocolo incompatible. Implementa captura configurable de webcam, dos colores con IDs estables, HSV editable/guardable, morfología, contornos/centroides/eje de orientación, seguimiento temporal y el mismo JSON UDP v1 de Godot. No envía geometría ni imágenes; no incorpora proyección u homografía.

No se modificó código de producción, física, combate, escenas o recursos de Godot. Dentro del proyecto Godot sólo se añadió un observador de pruebas y se actualizó el README. Las plataformas siguen bajo PlatformManager y sus límites físicos existentes.

## Pruebas ejecutadas

| Funcionalidad | Prueba realizada | Resultado |
|---|---|---|
| Verde / ID 1 | Imágenes BGR sintéticas, máscara HSV y contorno rectangular | FUNCIONA |
| Azul / ID 2 | Imágenes BGR sintéticas con trapecio | FUNCIONA |
| Centro / orientación | Comparación con centros conocidos y ángulos entre −89 y 89°, tolerancia de rasterización | FUNCIONA |
| Ruido / falsos candidatos | Puntos aislados, color incorrecto, fondo de color demasiado grande, candidato lejano y distractor mayor | FUNCIONA |
| Seguimiento | Confirmación inicial y de reaparición, suavizado, pérdida breve, no extrapolación, visible=false y ausencia de posición inventada inicial | FUNCIONA |
| Simetría | Continuidad de eje ±90°, conservación en cuadrados y rechazo de saltos angulares | FUNCIONA dentro de la ambigüedad de eje documentada |
| Configuración | Guardado/carga JSON, rangos inválidos, tipos enteros y valores no finitos | FUNCIONA |
| UDP | Socket real local, claves exactas de protocolo, secuencia creciente, límite de tamaño y temporizador con jitter | FUNCIONA |
| Cámara simulada | Apertura, lectura, desconexión, frame antiguo y liberación con dispositivos falsos | FUNCIONA |
| Interfaz HighGUI | Ventanas reales con imágenes sintéticas, movimiento programático de sliders, S guarda, L restaura, Q solicita salida | FUNCIONA; 5/5 |
| Cámara real, índice 0 | Apertura DirectShow y lectura de un frame de 640×480 | FUNCIONA; dispositivo liberado |
| Captura real sostenida | Diez segundos, sin guardar/transmitir imágenes | FUNCIONA con rendimiento inferior al objetivo; ver abajo |
| Colores de módulos físicos | No se colocaron piezas verdes/azules frente al dispositivo; las sesiones reales no detectaron IDs | NO SE PUDO PROBAR con piezas físicas |
| Backend MSMF | Intento de captura real acotado | FALLA en este equipo: cero frames y el hilo no volvió antes del cierre acotado; el proceso terminó con código 1 |
| Python → Godot | Imágenes sintéticas procesadas por OpenCV y tracker reales, emisor independiente, inspección MCP | FUNCIONA; 7/7 comprobaciones finales |
| Combate concurrente | Ambos jugadores sobre plataforma movida por la visión; ataque ligero y seguimiento UDP durante el impacto | FUNCIONA; 6% de daño, una sola aceptación de impacto |
| Regresión del juego | Menús, movimiento P1/P2, combate, vidas/victoria/reinicio, plataformas y gravedad controlada | FUNCIONA; 225/225 |
| Carga Godot | Headless: parsing, recursos, escena e inicio físico | FUNCIONA; 40 recursos cargados sin fallos en la pasada registrada |

La batería Python aprobó **21/21 pruebas**. Incluye subcasos de rotaciones, configuración inválida y paquetes; no se confunden esas pruebas con acceso físico a cámara. El acceso físico sí se probó por separado, con los resultados indicados.

## Medidas reales y límites

En la última integración sintética se procesaron **238 frames en 8.030 s**, promedio **29.641 FPS** y **238 paquetes enviados**, sin errores de envío. Un muestreo de Godot registró ambos IDs visibles, **29.507 paquetes/s**, cero inválidos y desplazamientos máximos observados de aproximadamente **157.98 px** y **123.85 px**. Se comprobó congelado al terminar el envío y conservación exacta de polígonos/dimensiones, con tolerancia numérica de Godot para escala unitaria.

La prueba física final con DirectShow procesó **88 frames en 10.647 s** incluyendo apertura/cierre; el promedio total fue **8.265 FPS** y la última ventana de procesamiento **14.816 FPS**. El tamaño leído fue **640×480** y `camera_closed=true`. Otra sesión anterior procesó 93 frames y midió 18.687 FPS en la última ventana. **No se alcanzaron ni se afirman 30 FPS sostenidos con esta cámara/controlador.** La configuración solicita 30; es un objetivo, no una medición. El pipeline sintético demuestra la capacidad medida por separado.

MSMF no proporcionó frames y dejó `camera_closed=false` antes de finalizar el proceso. No se debe interpretar como captura exitosa. Mantener DirectShow en este equipo; probar otros modelos/formatos de cámara queda pendiente. No se cambiaron permisos de Windows, firmware, configuraciones de privacidad ni parámetros del juego para obtener estos resultados.

Las sesiones de cámara real se ejecutaron con UDP desactivado y sin snapshots. No se guardaron ni enviaron imágenes de webcam. `artifacts/vision_synthetic.png` contiene únicamente una imagen generada para pruebas.

## Correcciones durante el desarrollo

- Se reemplazó el protocolo antiguo `{plataformas:[x,y,w,h]}` por el existente `{version,sequence,modules:[id,x,y,angle,visible]}`.
- El temporizador inicial de envío podía saltar frames por pequeñas variaciones del tiempo de procesamiento. Se corrigió la programación por plazos y se añadió una prueba con jitter; la repetición pasó de unos 20 a unos 29.5 paquetes/s medidos.
- La asociación de candidatos usa el último centro observado, separado del centro suavizado. Así el retraso del EMA no rechaza movimiento válido.
- La configuración exige enteros reales donde las APIs de cámara/sliders/socket los necesitan, evitando que JSON como `640.0` pase la validación y falle después.
- El observador de integración inicialmente comparaba sólo la pose final y la escala con igualdad binaria. Se corrigió para medir el desplazamiento máximo durante la trayectoria y tolerar exclusivamente el error flotante de rotación observado de **5.96×10⁻⁸**. Colliders y polígonos siguen comparándose exactamente. No se modificó producción para silenciar estas aserciones.
- Se corrigió una advertencia de sombreado de propiedad en el script de prueba. El último arranque MCP no indicó errores del proyecto.

## Archivos creados/modificados

- `detector.py`: entrada compatible al paquete nuevo; importar el archivo ya no abre una cámara.
- `requirements.txt`, `RunDetector.cmd`, `.gitignore`: dependencias, lanzador y exclusión de cachés/venv.
- `vision/config.py`, `config.json`: configuración y validación/guardado.
- `vision/detection.py`: contrato Detector/Observation y segmentación por color.
- `vision/tracking.py`: confirmación, asociación, suavizado y visibilidad.
- `vision/camera.py`: captura con hilo, último frame, reconexión y cierre.
- `vision/transport.py`: JSON UTF-8 y UDP v1.
- `vision/gui.py`, `app.py`, `synthetic.py`, `__init__.py`: interfaz, aplicación, fuente de imágenes de prueba y paquete.
- `vision/README.md`: instalación Windows, calibración, protocolo, orientación y límites.
- `tests/test_vision.py`, `tests/gui_smoke.py`, `tests/__init__.py`: pruebas.
- `juegofrei/validation/VisionIntegrationValidation.gd` y UID generado: observador y ataque real durante transmisión.
- `juegofrei/README.md`: enlace al detector; no cambios a scripts/escenas de producción.

Evidencia: `artifacts/vision_unit_results.json`, `vision_gui_results.json`, `webcam_probe.json`, `webcam_processing_final.json`, `webcam_msmf.json`, `vision_godot_sender_final.json`; `juegofrei/validation/vision_udp_results.json`, `full_vision_regression.json`, `headless_qa.json`.

## Pruebas manuales pendientes

1. Presentar **una pieza verde y una azul** bajo la iluminación real, calibrar HSV y comprobar que sólo esas piezas se identifican.
2. Comparar centros/ángulos con movimientos físicos conocidos. La orientación por color no tiene dirección única de 360°; cuadrados y piezas simétricas tienen mayor ambigüedad.
3. Probar oclusión física, reflejos, cruce de piezas, reconexión USB y cambios de iluminación con el modelo de cámara definitivo. Sólo se simularon desconexiones en las pruebas unitarias.
4. Ajustar cámara/backend/formato si se necesitan 30 FPS reales. No se modificó la física para compensar una fuente más lenta.
5. Hacer una partida presencial con dos jugadores y módulos reales. Las pruebas automatizadas sí verificaron combate durante recepción de poses detectadas en imágenes sintéticas.

ArUco está preparado como reemplazo de la interfaz de detección, pero no implementado. No se incorporaron homografía, proyección ni reconstrucción geométrica.
