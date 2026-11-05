# Auditoría integrada de estabilidad

Fecha: 30/10/2026. Godot 4.6.3 oficial en Windows, inspeccionado y ejecutado con Godot AI MCP. Python 3.14.5, OpenCV 5.0.0 y NumPy 2.5.3.

## Resultado

Se corrigieron captura bloqueada, seguimiento angular y drenado de paquetes; se agregó instrumentación de tiempos y edades. Se preservaron geometría, tamaño, gravedad, controles y combate. No se implementó proyector ni homografía.

La pasada final aprobó **37/37 pruebas UDP, 225/225 regresiones del juego, 7/7 de visión/combate concurrente y 7/7 del recorrido con pérdidas y reinicio**. Python aprobó **25/25** y HighGUI **5/5**. La batería UDP y las pruebas Python se repitieron después de las correcciones. El último headless registrado cargó **42 recursos** sin fallos.

## Funcionalidades verificadas

| Caso | Ejecución real | Resultado |
|---|---|---|
| Godot sin detector | Arranque MCP, menú inicial pausado, MOUSE y socket cerrado | FUNCIONA |
| Detector sin Godot | Webcam real, 8 s, UDP a puerto sin receptor; proceso termina sin errores de envío | FUNCIONA; TX no implica recepción |
| Ambos ejecutándose | Dos procesos de detector independientes, imágenes BGR por OpenCV real y UDP local | FUNCIONA |
| Verde | ID 1, movimiento y oclusión generada en la imagen | FUNCIONA con imágenes sintéticas |
| Azul | ID 2, movimiento y oclusión generada en la imagen | FUNCIONA con imágenes sintéticas |
| Movimiento simultáneo | Ambos módulos visibles y plataformas desplazándose | FUNCIONA |
| Rotación | Ángulos recibidos de ambos módulos; prueba de rotación continua y reacquisición angular | FUNCIONA dentro de la ambigüedad de eje por color |
| Pérdida breve | Oclusión verde de 80 ms; tolerancia HOLD sin extrapolación | FUNCIONA |
| Pérdida prolongada | Oclusiones verde y azul por separado; visible=false, pose congelada y collider conservado | FUNCIONA |
| Recuperación | Confirmación y seguimiento recuperado; movimiento de superficie acotado | FUNCIONA |
| Cierre del detector | Estado final no visible y watchdog de Godot | FUNCIONA |
| Reinicio del detector | Segundo proceso, secuencia nueva, mismo receptor sin reiniciarlo | FUNCIONA |
| MOUSE/EXTERNAL | F2, clic, arrastre, Q/E bloqueados en EXTERNAL, API rechaza fuente incorrecta | FUNCIONA |
| Jugadores sobre plataformas | Transporte lateral, subida/bajada, inclinación, recuperación de seguimiento | FUNCIONA |
| Combate móvil | Ataque ligero durante poses detectadas en vivo, daño 6% una sola vez; ataque fuerte en batería UDP | FUNCIONA |
| Menús, pausa, victoria, reinicio | Clics y teclado en regresión de 225 comprobaciones, incluidos empate y vidas | FUNCIONA |
| Desconexión/bloqueo de cámara | Drivers falsos bloqueados en open/read; reinicio automático y cierre acotado | CORREGIDO Y VERIFICADO con fallos simulados |
| MSMF real bloqueado | Sin frames; watchdog reinició el proceso, cierre exitoso y ningún hijo vivo | Bloqueo de aplicación corregido; captura MSMF sigue sin funcionar en este equipo |

Los movimientos de piezas físicas de colores y la extracción física del cable USB no se pudieron ejecutar de forma presencial. No se presentan las imágenes sintéticas como una prueba de reconocimiento físico.

## Correcciones aplicadas

1. **Cámara nativa bloqueada:** el hilo anterior no podía cancelarse cuando OpenCV quedaba dentro de open/read. Ahora la captura vive en un proceso hijo con un único frame compartido; el padre lee sin esperar un lock ocupado. Watchdogs de arranque/lectura reinician el proceso. Al cerrar se intenta liberar normalmente y, si está bloqueado, se termina el hijo. Las métricas distinguen reinicios y cierres forzados. No se deja esperando al hilo principal.
2. **Rotaciones válidas frenadas:** el límite angular se aplicaba contra el ángulo suavizado, cuyo retraso podía rechazar un giro continuo válido. Se separó el ancla angular observada del valor filtrado y se permite reacquisición después de observaciones consistentes. Se añadieron pruebas de giro sostenido, cambio angular durante pérdida y rechazo de saltos falsos.
3. **Cola UDP reordenada:** al drenar por presupuesto se descartaba el candidato de mayor secuencia del primer bloque. Ahora se conserva entre ciclos hasta completar el drenado. Se evita además comprobar el estado de la cola dos veces con resultados inconsistentes por llegadas concurrentes.
4. **Datos viejos:** campos opcionales `sent_unix_ms` y `source_age_ms` permiten rechazar datagramas de más de 350 ms y frames de más de 250 ms. Los v1 anteriores siguen siendo admitidos; los cinco campos de módulo no cambiaron. Los plazos son configurables y no afectan el reloj de física.
5. **Jitter pequeño:** zona muerta configurable de 0.35 px y 0.15° en objetivos externos; renueva el seguimiento aunque suprima un cambio insignificante. Se conserva el suavizado y los límites físicos existentes.
6. **Diagnóstico:** tiempos de lectura, procesamiento OpenCV, edad del frame, envío, frecuencia capturada/enviada/recibida/aplicada y estado por módulo. Muestras acotadas a 600; logs cada dos segundos configurables, no por frame. Godot muestra datos desconocidos con «—», no como cero.
7. **Advertencias:** se corrigieron ternarios con tipos int/float incompatibles detectados en la inspección MCP.

## Colisiones y aplastamientos

Durante el recorrido se reprodujo un aplastamiento real: la plataforma derecha, inclinada, transportó al jugador contra el borde de la superior. La traza confirmó simultáneamente la plataforma de apoyo, la intrusión y coincidencia entre pose visual/física. No era jitter de red.

La protección existente actuó una vez, desplazó brevemente al jugador a un punto libre y no quitó vidas. Se verificaron **cero encajamientos permanentes**, rescate acotado y conservación de colliders. No se eliminaron colisiones ni se cambiaron tamaños para ocultar el caso. Las trazas quedan en `UnstuckGuard.last_recovery` y sólo se actualizan ante una recuperación.

**Límite conocido:** cuando un operador coloca plataformas de modo que aprisionan físicamente un personaje, puede actuar este rescate corto del personaje. No se garantiza continuidad absoluta del personaje en una configuración geométricamente imposible. Las plataformas sí conservan su movimiento acotado: el máximo medido de traslación más giro de su superficie fue aproximadamente **4.00003 px/tick**, dentro de tolerancia numérica del límite de 4.

Una aserción inicial exigía cero rescates aun en ese aplastamiento; se corrigió el criterio a rescate acotado, personaje libre y vidas conservadas. Otra prueba suponía arena inicial después de un reinicio, cuando el juego preserva deliberadamente el diseño del operador; ahora establece explícitamente su fixture antes de medir movimiento. No se cambiaron esas conductas de producción para forzar las pruebas.

## Métricas medidas

| Medida | Resultado y contexto |
|---|---|
| Godot, bucle | **60.005 FPS medios**, 1315 muestras en **21.915 s** de la sesión con detector/reinicio |
| Godot, dibujado | **1866 frames dibujados en 31.083 s**, aproximadamente **60.033 FPS**; incluye arranque/espera de la sesión |
| Física | **60 ticks/s configurados**, **60.005 Hz medidos** en el intervalo de muestreo |
| Tiempo de frame | P95 **17.854 ms**, máximo **19.599 ms** en esa pasada; no implica garantía universal ni duración ilimitada |
| Detector sintético 1 | **29.552 FPS**, OpenCV medio **7.803 ms**, P95 **11.068 ms**; envío **29.571 Hz** |
| Detector sintético 2 | **29.530 FPS**, OpenCV medio **8.050 ms**, P95 **11.241 ms**; envío **29.582 Hz** |
| Envío local | Aproximadamente **0.185 ms** de llamada sendto media; no es tiempo de recepción ni ACK |
| Captura real DirectShow | **640×480**, 113 frames capturados, **19.101 Hz** de captura medidos, 111 procesados |
| Lectura real | Media **52.214 ms**, P95 **73.079 ms**; incluye espera del driver y entrega del frame |
| OpenCV con webcam | Media **9.732 ms**, P95 **20.051 ms** en la sesión medida |
| Edad desde read hasta procesamiento | Media **28.472 ms**, P95 **50.166 ms** |
| Procesamiento real | Última ventana **19.721 FPS**; promedio total **8.780 FPS** incluyendo apertura/cierre |
| Cierre real | DirectShow: normal, cero reinicios/cierres forzados, ningún proceso hijo vivo |
| MSMF | Cero frames; reinicio/cierre forzado registrado, `camera_closed=true`, ningún hijo vivo; no se cuenta como captura exitosa |

**El objetivo de 30 FPS no se alcanzó en la webcam real con esta configuración.** La captura sigue siendo más lenta que el objetivo; no se compensó alterando la física. El ensayo sintético estuvo cerca de 30 FPS. Las mediciones de Godot corresponden sólo a la máquina y los intervalos registrados.

La edad de recepción de Godot no es latencia extremo a extremo. `source_age_ms` empieza al devolver read, no en la exposición del sensor; `sent_unix_ms` usa el reloj del mismo equipo y admite ajustes del sistema. Se usan tiempos monotónicos para física, seguimiento, watchdog y duración. En clientes v1 sin fecha no se puede inferir cuánto tiempo pasó en el kernel antes del primer desencolado.

## Archivos modificados

- Python: `vision/camera.py`, `capture_worker.py` (nuevo), `tracking.py`, `transport.py`, `metrics.py` (nuevo), `app.py`, `gui.py`, `config.py`, `config.json`, `synthetic.py`.
- Godot: `scripts/ExternalPlatformReceiver.gd`, `PlatformInputPanel.gd`, `UnstuckGuard.gd` (traza de recuperaciones). No se tocaron geometría, dimensiones, ataques ni parámetros de gravedad.
- Pruebas: `tests/test_vision.py`, `camera_fakes.py`, `run_stability_stream.py`; `validation/ExternalInputValidation.gd`, `StabilityStreamValidation.gd`, `StabilitySuite.gd` y UID generados.
- Documentación: `vision/README.md`, este informe y `CALIBRATION_PREPARATION.md`.

Evidencia: `artifacts/stability_python_tests.json`, `vision_gui_results.json`, `stability_detector_alone.json`, `stability_camera_measured.json`, `stability_msmf_bounded.json`, `stability_sender1/2.json`, `stability_restarts.json`; `juegofrei/validation/stability_suite_results.json`, `stability_stream_results.json`, `vision_udp_results.json`, `external_integration_results.json`, `headless_qa.json`.

## Pendientes físicos y calibración

- Calibrar HSV y verificar verde/azul con las piezas reales bajo la iluminación definitiva; no se detectaron piezas físicas en las sesiones de cámara disponibles.
- Desenchufar/reconectar físicamente la webcam, probar oclusiones reales, reflejos y cruces. Las pérdidas y bloqueos automatizados usaron imágenes y drivers falsos claramente identificados.
- Investigar cámara/backend/formato si se requieren 30 FPS reales. MSMF continúa sin entregar frames en este dispositivo.
- Una partida presencial con dos jugadores y módulos físicos. Las pruebas automáticas sí ejercitaron combate durante movimiento de plataformas por visión.
- La orientación por color continúa siendo ambigua módulo 180° y en piezas simétricas. No se promete orientación única 360°.
- Preparación documentada en `CALIBRATION_PREPARATION.md`: resolución, convenciones de coordenadas, mediciones y punto de inserción de una transformación futura. No se implementó calibración óptica, homografía ni proyector.

Referencias de APIs: [multiprocessing](https://docs.python.org/3/library/multiprocessing.html), [relojes Python](https://docs.python.org/3/library/time.html), [Time de Godot 4.6](https://docs.godotengine.org/en/4.6/classes/class_time.html).
