# Estado del proyecto para continuar en otro chat

Revisión de archivos: 05/11/2026. Los resultados de pruebas citados provienen de ejecuciones guardadas, principalmente del 30/10/2026; no se repitieron hoy las pruebas de hardware. No se modificó el juego para elaborar este informe.

## Objetivo y situación general

Videojuego local de combate 2D, inspirado en platform fighters, con dos personajes cuadrados. Una tercera persona modifica la arena moviendo o rotando plataformas mediante mouse o módulos físicos reconocidos por una webcam. El montaje definitivo previsto es una pared con proyección HDMI.

El juego, el reconocimiento por colores, la transmisión UDP y la calibración geométrica están implementados. La principal incertidumbre actual está en el funcionamiento físico conjunto: seguimiento simultáneo estable, iluminación y primera alineación cámara-proyector sobre la pared.

## Ubicación y entorno

- Raíz: `C:\godot 4.6\juego frei`.
- Proyecto Godot: `C:\godot 4.6\juego frei\juegofrei`.
- Motor utilizado: Godot 4.6.3; GDScript tipado; Windows.
- Visión: Python 3, opencv-python y NumPy. Dependencias declaradas en requirements.txt. OpenCV instalado durante las pruebas: 5.0.0, con ArUco disponible.
- Lienzo lógico: 1280 × 720. Física: 60 ticks/s. Juego limitado a 60 FPS; no equivale a una garantía de rendimiento en cualquier equipo.
- Cámara configurada: REDRAGON Live Camera USB, DirectShow, índice 2, captura 640 × 480, objetivo 30 FPS y sin espejo. Su capacidad nominal de 1080p no significa que se esté capturando a esa resolución. El índice puede cambiar al conectar dispositivos.

## Juego implementado

- Dos jugadores simultáneos; aceleración/desaceleración, salto variable, doble salto, coyote time, jump buffering, control aéreo, plataformas atravesables y descenso voluntario.
- Caída lenta y controlable: mantener abajo acelera progresivamente; soltarlo frena hacia el límite normal. Parámetros actuales: gravedad de ascenso 1250, descenso 1450 px/s²; caída normal máxima 640 y fast fall 800 px/s.
- Ataques ligeros/fuertes, aéreos y direccionales; dodge; hitboxes/hurtboxes; daño acumulado; knockback; hitstun; invulnerabilidad; hitstop y efectos geométricos.
- Tres vidas, reaparición, victoria o empate y reinicio. Un ataque no debe dañar dos veces a la misma víctima por la misma activación. Los golpes simultáneos se resuelven después de procesar ambos personajes.
- Menú principal, controles, pausa/reanudación, reinicio y regreso al menú. Reiniciar conserva la disposición de plataformas elegida por el operador.

Controles: P1 A/D, W/S, F ligero, G fuerte, H dodge. P2 flechas, K ligero, L fuerte y Shift derecho dodge. Esc pausa, F1 controles, R reinicia tras resultado. Mouse arrastra; Q/E rota; Tab muestra/oculta edición; F2 alterna MOUSE/EXTERNAL y F3 oculta el diagnóstico.

## Plataformas y física

Las tres plataformas están predefinidas: left, right y top. La visión reconoce dos módulos: **verde ID 1 → left; azul ID 2 → right**. Top no tiene módulo de color asignado por el detector actual.

Solo cambia posición y rotación. Se conservan forma, tamaño y escala. DynamicPlatform usa AnimatableBody2D, objetivos suavizados, límites de velocidad y una sola escritura de transformación por tick. Valores actuales: 180 px/s, 0,70 rad/s y recorrido máximo de superficie de 4 px/tick.

MOUSE y EXTERNAL son excluyentes. PlatformManager rechaza fuentes incorrectas, IDs desconocidos y transformaciones con escala/deformación. El movimiento externo no crea plataformas.

Existe un recuperador de atrapamiento persistente. En una prueba con plataformas que se cruzaban evitó un aplastamiento mediante un pequeño desplazamiento del personaje, sin perder vidas. Esto evita bloqueos, pero no elimina toda situación geométricamente imposible ni garantiza una percepción perfecta de colisión.

## Reconocimiento y seguimiento

Flujo: webcam BGR → HSV → máscaras verde/azul → apertura/cierre → contornos → validación regional → seguimiento temporal → transformación opcional → UDP → receptor → PlatformManager → física.

Hay filtros configurables por color: área mínima/máxima, saturación, dimensiones, relación de aspecto, llenado y confianza. Confianza significa cobertura/pureza, no probabilidad de identificación. Si las máscaras se superponen se rechaza el contorno; dos candidatos comparables del mismo color pueden rechazarse por ambigüedad. El seguimiento valida el ID interno de las observaciones.

La adquisición requiere 3 observaciones coherentes por defecto. Se conserva la última pose durante pérdidas breves; después de 150 ms sin observación válida se marca no visible. No se extrapola ni se toma la pose del otro módulo. Tras pérdida completa, la recuperación requiere confirmación y mantiene suavizado. El receptor también congela cuando se interrumpe el emisor.

Calibración HSV: sliders independientes, máscaras, contornos aceptados/rechazados, áreas, centros, IDs y estados. Se puede muestrear una región con el mouse para sugerir HSV; A aplica explícitamente, S guarda y L carga. D oculta detalles y Q cierra. El archivo es vision/config.json.

La captura está aislada en un proceso hijo, con un único fotograma compartido y watchdog. Así una llamada nativa de cámara bloqueada no impide cerrar el detector. DirectShow entregó imágenes en las pruebas; MSMF no entregó fotogramas, aunque el cierre quedó acotado. La desconexión USB física todavía necesita prueba específica.

## Comunicación y coordenadas

UDP local 127.0.0.1:5005; JSON UTF-8, frecuencia objetivo 30 envíos/s. Se validan estructura, tipos, rangos, IDs, duplicados y secuencias. Se rechazan paquetes viejos; se prioriza el estado válido más reciente. El receptor funciona en física y no reproduce una cola de posiciones después de la pausa.

- CAMERA: modo predeterminado, UDP v1. x/y normalizados respecto de la captura; Godot los expande al rectángulo de arena (150,180,980,340). No representa toda la ventana.
- PROJECTOR: UDP v2. Exige coordinate_space=PROJECTOR, projection_size=[1280,720] y orientation_space=PROJECTOR_PIXELS. x/y abarcan el lienzo completo, normalizados por 1279/719. Python ya transformó centro y orientación; **Godot no debe aplicar otra homografía ni la expansión de CAMERA**.
- Los módulos conservan id, x, y, angle y visible. Los emisores v1 anteriores sin campo de espacio siguen interpretándose como CAMERA.
- Un módulo fuera del dominio calibrado se envía invisible. Si el centro proyectado queda fuera de los límites de movimiento de arena, Godot lo congela en lugar de recortarlo a una posición incorrecta.

Los tiempos del diagnóstico distinguen antigüedad de observación/recepción. No representan latencia física de extremo a extremo ni tiempo de exposición de cámara. Hay trazas JSONL opcionales y contadores por plataforma para comprobar qué ID y secuencia originaron una transformación.

## Calibración cámara-proyector implementada

Proceso separado del combate. Godot ofrece selector de monitor, vista previa y pantalla completa. El patrón contiene 8 ArUco DICT_4X4_50: IDs 10–13 para ajustar H y 14–17 para verificar, sin usarlos en el ajuste. **ArUco se utiliza actualmente para calibración; los módulos físicos siguen identificándose por color.**

OpenCV detecta las referencias y sus centros proyectivos; hay selección manual alternativa. cv2.findHomography calcula H con RANSAC; cv2.perspectiveTransform transforma posición y eje de orientación. No se reutiliza directamente el ángulo de cámara.

Se comprueban distribución espacial, degeneración, horizonte, orientación, compatibilidad y errores independientes. Límites actuales: ajuste máximo 3 px; verificación RMS 3 px y máximo 4 px. Son píxeles del lienzo lógico 1280×720, no necesariamente píxeles nativos HDMI ni milímetros.

SPACE detecta/congela, M selección manual de centros 10–17, R repite, S confirma y guarda, L carga/revalida y Q cancela/cierra. JSON de homografía independiente del HSV, con resoluciones, matriz, puntos, errores, fecha y parámetros de cámara. Cancelar antes de confirmar conserva el archivo anterior.

**Todavía no existe una homografía física guardada en vision/projector_calibration.json.** La existente en artifacts/synthetic_projection_calibration.json es una prueba sintética y no sirve para alinear el montaje real. En la última comprobación de pantallas se detectaba solo el monitor 0, 1366×768; no se verificó físicamente un segundo monitor/proyector.

## Evidencia de pruebas y límites

Pruebas físicas con Redragon:

- Solo verde: 294 paquetes recibidos; 85 transformaciones a left y 0 a right. Azul conservó su transformación.
- Solo azul: 291 paquetes; 62 transformaciones a right y 0 a left. Verde conservó su transformación.
- Ambos: se confirmaron ambos IDs y hubo pérdida/recuperación del azul, pero verde permaneció adquirido muy poco tiempo. **No está validado el seguimiento físico simultáneo estable.** Sin video continuo no puede atribuirse cada pérdida a encuadre, oclusión o filtro.
- Captura real medida cerca de 20 FPS a 640×480; no se alcanzaron ni se afirman 30 FPS de webcam. Se enviaron poses con una frecuencia distinta a la de observaciones nuevas.

Últimas comprobaciones automatizadas guardadas: 59 pruebas Python (incluyen 19 de geometría), 10 de interfaz HSV, 4 de interfaz geométrica, 8 de escena de calibración, 12 del receptor PROJECTOR, 37 UDP anteriores, 225 regresiones de juego y carga headless de 47 recursos. Las cantidades corresponden a grupos que pueden compartir cobertura; no sumarlas como si fueran funcionalidades distintas.

La integración sintética PROJECTOR pasó 7 comprobaciones con ambas plataformas y combate sobre plataforma móvil. Se auditaron 120 aplicaciones contra sus paquetes y centros de origen para verificar ID y transformación única. El ensayo procesó aproximadamente 29,4 FPS. Nada de esto demuestra precisión física sobre pared. Hubo mediciones previas cercanas a 60 FPS del juego en este equipo, no una garantía para cualquier montaje.

## Pendientes y decisiones para discutir

1. Estabilizar la captura conjunta de ambos módulos con encuadre, iluminación y piezas definitivas. Registrar candidatos/estados y movimientos antes de cambiar filtros a ciegas.
2. Decidir si conservar identificación por colores o evaluar marcadores para identificar también los módulos. Un objeto del entorno del mismo color y geometría compatible puede seguir generando falsos positivos. Piezas simétricas mantienen ambigüedad de orientación de 180°.
3. Conectar el proyector, fijar cámara/proyector y calibrar sobre la pared. Después comprobar centros y ángulos en varios puntos independientes antes de jugar.
4. Probar si la imagen del juego proyectada contamina las máscaras de color. Esta posible realimentación aún no se evaluó físicamente.
5. Medir error real, pérdida/recuperación, desconexión/reconexión USB, frecuencia de observaciones y demora visible. Los paquetes/s no equivalen a fotogramas nuevos/s.
6. Evaluar si la lente requiere corrección de distorsión. Actualmente no existe. Pared no plana o módulos alejados del plano producen errores que una homografía no resuelve por sí sola.
7. Tras validar el montaje, repetir colisiones con jugadores encima y combate con los módulos físicos. Después ajustar rendimiento, balance y exportación Windows.

Recomendación basada en el estado observado: priorizar una validación física reproducible del reconocimiento y la geometría antes de ampliar el combate o reestructurar sistemas que ya pasan sus regresiones. La siguiente etapa debería producir medidas y evidencia del montaje real, no solo más pruebas sintéticas.

## Restricciones que se deben conservar

- No cambiar geometrías, tamaños ni escalas de plataformas.
- Conservar la caída lenta/controlada y el movimiento existente.
- Mantener combate, menús, dos jugadores y modo MOUSE.
- Reutilizar PlatformManager y el receptor; no crear otro flujo de control incompatible.
- No dar por aprobadas pruebas físicas que no se realizaron.
- No hay base relacional, cuentas ni guardado de partidas: la persistencia actual es JSON. El diagrama ER de la entrega académica es conceptual.

## Archivos para orientarse

Python: detector.py; vision/app.py; vision/config.json; vision/detection.py; vision/tracking.py; vision/camera.py; vision/capture_worker.py; vision/transport.py; vision/gui.py; vision/projection.py; vision/projection_pattern.py; vision/projector_calibration.py.

Godot: juegofrei/scenes/Main.tscn, Player.tscn, Arena.tscn, DynamicPlatform.tscn y ProjectionCalibration.tscn; juegofrei/scripts/PlatformManager.gd, DynamicPlatform.gd, ExternalPlatformReceiver.gd, MousePlatformController.gd, PlayerController.gd, PlayerMovement.gd, CombatController.gd, DamageModel.gd, GameManager.gd y GameShell.gd. Los ajustes de movimiento están en juegofrei/resources/PlayerMovement.tres.

Pruebas/evidencia: tests/; juegofrei/validation/; artifacts/projection_qa_summary.json; vision/PROJECTOR_QA_REPORT.md; vision/COLOR_ISOLATION_REPORT.md; vision/STABILITY_REPORT.md. Algunos informes antiguos describen etapas anteriores: el estado de proyección más reciente está en PROJECTOR_QA_REPORT.md y PROJECTOR_GUIDE.md.

Se utilizó Godot AI MCP para ejecutar, inspeccionar e inyectar entradas durante el desarrollo. Otro chat con acceso al equipo debe descubrir sus herramientas y comprobar la sesión/proyecto abierto antes de modificarlo; no asumir que los resultados guardados describen una nueva ejecución.

## Comandos principales

Desde `C:\godot 4.6\juego frei`:

```powershell
# Enumerar cámaras y verificar el índice de Redragon
python -m vision.list_cameras

# Calibrar HSV sin mover el juego
python detector.py --no-udp

# Detector normal: CAMERA, UDP v1
python detector.py

# Diagnóstico opcional con traza, sin guardar imágenes
python detector.py --trace artifacts/detecciones.jsonl

# Calibración geométrica: reemplazar 1 por el índice real de salida
.\CalibrateProjector.cmd --screen 1

# Juego en el mismo monitor y pantalla completa
& "C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe" --path "C:\godot 4.6\juego frei\juegofrei" --screen 1 --fullscreen

# Solo después de obtener una calibración física válida
python detector.py --coordinates PROJECTOR --calibration vision/projector_calibration.json

# Regresiones Python
python -m unittest tests.test_vision tests.test_color_isolation tests.test_projection -v
```

En Godot iniciar partida y seleccionar EXTERNAL con F2 para recibir el detector. Cerrar la calibración antes de usar la cámara desde el detector normal. No ejecutar ambos procesos de captura sobre la misma webcam.

## Pregunta sugerida para el siguiente chat

"Con este estado, ayudame a elegir la siguiente etapa para obtener un montaje físico estable sobre pared. Compará mantener seguimiento por color con evaluar marcadores para los módulos; proponé una prueba reproducible para distinguir errores de detección, homografía y física. No rehagas el combate ni cambies geometrías o gravedad. Separá decisiones de diseño, pruebas físicas necesarias y cambios de código justificados por evidencia."
