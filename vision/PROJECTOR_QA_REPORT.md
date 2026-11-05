# Calibración geométrica — validación 2026-10-30

Estado: sistema de software implementado y validado. **Primera calibración física con proyector HDMI + webcam sobre pared pendiente.** El único monitor detectado fue índice 0, 1366×768, DPI 96. Cámara configurada: Redragon DirectShow índice 2, 640×480, sin espejo; no se abrió la webcam durante esta etapa.

Instrucciones completas: [PROJECTOR_GUIDE.md](PROJECTOR_GUIDE.md).

## Implementación

- Escena de calibración independiente sin jugadores ni receptor UDP. Lista monitores, muestra patrón en una ventana nativa o pantalla completa y permite ocultar/cancelar la salida.
- Patrón generado internamente, sin assets externos: ArUco DICT_4X4_50, IDs 10–13 para ajuste y 14–17 para verificación independiente. Zonas blancas de protección para no mezclar los marcadores con el contorno del área útil.
- Detector automático de referencias con identificación, rechazo de duplicados y cálculo del centro proyectivo. Alternativa manual de ocho centros ordenados, sobre imagen congelada.
- Candidato separado del archivo: SPACE captura; R repite; S confirma solo si es válido; L carga/revalida; Q cancela sin cambiar el archivo anterior si no se confirmó con S.
- Homografía cámara-píxeles → lienzo lógico de proyección, cv2.findHomography/RANSAC. Control de cantidad, distribución, independencia, error, degeneración, horizonte y orientación de ejes. Espejo explícito soportado y comprobado.
- cv2.perspectiveTransform transforma centro y eje local de orientación. No se reutiliza el ángulo de cámara ni se modifica la forma o tamaño de las plataformas.
- Persistencia JSON atómica e independiente del HSV; errores recalculados al cargar. Captura, resolución lógica, índice, backend y espejo incompatibles se rechazan.
- CAMERA predeterminado mantiene UDP v1. PROJECTOR usa v2 explícito, resolución [1280,720] y orientación PROJECTOR_PIXELS. Módulos conservan id/x/y/angle/visible. Godot no calcula H ni aplica dos veces la normalización anterior.
- Fuera de la homografía se emite visible=false. Fuera de la arena permitida, Godot congela y registra outside_arena; evita una posición falsa por recorte. MOUSE y las físicas existentes permanecen intactos.

## Pruebas realmente ejecutadas

| Grupo | Resultado | Evidencia |
|---|---|---|
| Geometría Python | 19/19, repetidas | tests/test_projection.py, artifacts/projection_python_tests.log |
| Regresiones Python de color/cámara/seguimiento/UDP | 40/40; pasada conjunta 59/59 | artifacts/projection_python_tests.log |
| Ventanas HSV existentes | 10/10 | artifacts/vision_gui_results.json |
| Interfaz geométrica HighGUI con imagen sintética | 4 comprobaciones aprobadas: ventana, auto/S, R/L y cancelación manual | artifacts/projector_gui_results.json |
| Escena Godot mediante MCP | 8/8, dos pasadas: monitores, textura, vista previa, pantalla completa, aspecto, ocultar y separación del combate | juegofrei/validation/projection_scene_results.json |
| Patrón renderizado realmente por Godot, leído con OpenCV | 8 IDs reconocidos, lienzo renderizado 960×540; máximo independiente ≈1,61e-13 píxeles lógicos | artifacts/projector_render_results.json |
| Receptor Godot PROJECTOR | 12/12, dos pasadas: unidades, orientación, movimiento limitado, secuencias, errores de metadatos, límites y vuelta a MOUSE/CAMERA | juegofrei/validation/projection_input_results.json |
| Detector sintético completo → homografía no trivial → UDP v2 → juego | 7/7: ambos colores, movimiento, cierre/congelación, geometría fija, jugadores y ataque ligero único sobre plataforma móvil | juegofrei/validation/vision_udp_results.json |
| Auditoría de aplicaciones reales del ensayo anterior | 120/120 aplicaciones asociadas a ID/secuencia/fotograma; centro transformado exactamente una vez | artifacts/projected_trace_results.json |
| Compatibilidad UDP v1 | 37/37 | juegofrei/validation/external_integration_results.json |
| Menús, controles, física y combate | 225/225 | juegofrei/validation/external_integration_results.json |
| Headless carga/parsing/instanciación/arranque físico | 47 recursos, sin fallos | validación HeadlessAudit.gd ejecutada con Godot 4.6.3 |
| Errores de ejecución MCP | Sin errores en los runs inspeccionados de calibración y juego | logs_read source=game |

Los casos geométricos incluyen identidad, traslación, escala, perspectiva, rotación de ejes, exclusión del dominio, correspondencias incorrectas, matriz degenerada, resolución/cámara/espejo incompatibles, guardado/carga/cancelación, orientación, independencia de los verificadores, ArUco con perspectiva/duplicados y UDP v2 real por loopback. Las pruebas manuales usan callbacks automatizados y modos de la ventana, no una selección física de puntos por una persona.

## Métricas e interpretación

Ensayo sintético completo: 236 fotogramas en 8,02 s, ≈29,43 FPS de procesamiento y ≈29,47 envíos/s. OpenCV detección de color: media 10,51 ms / P95 15,08 ms. No se midieron FPS de render ni captura de webcam en esta etapa.

Comparación de 120 aplicaciones Godot con sus paquetes: error máximo de posición ≈0,0000321 px por precisión numérica; diferencia angular máxima ≈0,1488°, dentro del deadband existente de 0,15°. Este resultado compara software y datos sintéticos; **no es precisión física cámara-proyector**.

El error de calibración se expresa en píxeles lógicos 1280×720. No debe publicarse como píxel nativo HDMI ni error milimétrico. La conversión depende de la escala uniforme y las bandas del monitor. Ambos modos de salida usan el mismo aspecto que el juego.

## Límites y pendientes físicos

- No había proyector conectado; selección de un segundo monitor y proyección sobre pared no verificadas físicamente. El selector y pantalla completa se ejecutaron en el único monitor disponible.
- Mover cámara/proyector, cambiar monitor, posición/tamaño de ventana, zoom, keystone o resolución física requiere repetir calibración. Esos cambios físicos no se detectan todos automáticamente; no guardar un candidato antiguo después de cambiar salida.
- No se agregó corrección de distorsión de lente. La validación independiente puede rechazar una lente muy distorsionada o un plano no adecuado; no relajar límites para ocultarlo.
- Piezas fuera del plano calibrado producen paralaje. Color/simetría mantienen ambigüedad de identificación/orientación; la geometría no resuelve falsas detecciones ni orientación única de 360°.
- Verificar HSV bajo la proyección real: los colores del propio juego proyectado pueden interferir con detección por color. El seguimiento simultáneo físico sigue requiriendo prueba en el montaje definitivo.
- Confirmar centros y orientaciones en varios puntos; después probar pérdida/recuperación y combate con plataformas físicamente controladas. Ninguna prueba sintética sustituye estas comprobaciones.
- La homografía sintética está solo en artifacts/synthetic_projection_calibration.json. No se guardó una calibración física ficticia en vision/projector_calibration.json.

## Archivos modificados o creados

Producción Python:

- vision/projection.py — ajuste, validación, persistencia, transformación de centro/eje y exclusión de dominio.
- vision/projection_pattern.py — patrón y detector de referencias.
- vision/projector_calibration.py — cámara/imagen, interfaz automática/manual y confirmación.
- vision/app.py — CAMERA/PROJECTOR, compatibilidad, transformación única y diagnóstico/traza.
- vision/transport.py — espacio explícito y protocolo v2 compatible.
- CalibrateProjector.cmd — lanzador Windows.

Godot:

- juegofrei/scripts/ProjectionCalibration.gd y scenes/ProjectionCalibration.tscn — salida de calibración.
- juegofrei/calibration/projector_pattern.png — patrón generado; import y UID gestionados por Godot.
- juegofrei/scripts/ExternalPlatformReceiver.gd — validación v1/v2 y mapeo por espacio.
- juegofrei/scripts/PlatformInputPanel.gd — espacio recibido y contador de fuera de arena.

Pruebas:

- tests/test_projection.py, tests/projector_gui_smoke.py, tests/check_projected_trace.py.
- juegofrei/validation/ProjectionSceneValidation.gd, ProjectionInputValidation.gd.
- Nuevos reportes, trazas e imágenes generadas en artifacts/ y juegofrei/validation/.

Documentación: vision/PROJECTOR_GUIDE.md, vision/PROJECTOR_QA_REPORT.md, vision/README.md, vision/CALIBRATION_PREPARATION.md y juegofrei/EXTERNAL_INPUT.md.

Sin cambios de combate, gravedad, geometrías, dimensiones, Input Map de combate ni escena principal. Sin dependencias adicionales: OpenCV instalado expone ArUco; requirements.txt existente conserva validez.
