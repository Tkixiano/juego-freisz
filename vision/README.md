# Detector de módulos de colores → Godot

Proceso Python independiente. Verde **ID 1 / left**; azul **ID 2 / right**. Emite posición, orientación y visibilidad por UDP v1, con tiempos opcionales de diagnóstico compatibles con el receptor existente. La tercera plataforma no se controla con este detector. No modifica geometría ni el combate. Ver [la última auditoría de estabilidad](STABILITY_REPORT.md) y [la preparación de calibración](CALIBRATION_PREPARATION.md).

La calibración geométrica está disponible como proceso separado: ver [PROJECTOR_GUIDE.md](PROJECTOR_GUIDE.md). El detector conserva CAMERA como predeterminado (UDP v1); `--coordinates PROJECTOR --calibration vision/projector_calibration.json` transforma centro y orientación una sola vez y emite UDP v2 explícito. La calibración física sobre pared aún está pendiente.

## Instalación en Windows

Usar Python 3 de 64 bits, recomendado 3.11 o posterior, con soporte gráfico de OpenCV. Desde PowerShell:

```powershell
cd "C:\godot 4.6\juego frei"
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe detector.py
```

No hace falta activar el entorno ni cambiar políticas de ejecución de PowerShell. Usar **opencv-python**, no la variante headless: se necesitan ventanas y deslizadores. No instalar simultáneamente varios paquetes que proporcionen `cv2` dentro del mismo entorno.

`RunDetector.cmd` usa `.venv` si existe, o el Python del sistema. Acepta los mismos argumentos. La configuración predeterminada está en `vision/config.json`.

## Uso

La revisión de independencia de colores y sus resultados reales están en [COLOR_ISOLATION_REPORT.md](COLOR_ISOLATION_REPORT.md).

1. Primero calibrar sin mover el juego: `python detector.py --no-udp`.
2. Colocar una pieza verde y otra azul, sobre un fondo que no comparta esos colores.
3. Ajustar los seis deslizadores de cada ventana HSV. H va de 0 a 179; S/V de 0 a 255. H min > H max permite un rango que cruza el cero. S/V se mantienen ordenados.
4. **S** guarda la configuración JSON de forma atómica. **L** carga HSV y área mínima desde ese archivo y actualiza los deslizadores. Los cambios de cámara, red o seguimiento del JSON requieren reiniciar el proceso. Se usa `--config ruta.json` para otra calibración.
5. Cerrar con **Q** o Escape. Luego iniciar `python detector.py`, abrir una partida en Godot y seleccionar **EXTERNAL con F2**.

Calibración ampliada: **1** selecciona verde, **2** azul. Arrastrar con el botón izquierdo una región en la imagen principal calcula mediana y percentiles HSV. La ventana Calibration muestra la máscara seleccionada y una sugerencia; **A** la aplica explícitamente, **S** guarda y **L** carga. Muestrear el interior coloreado, evitando bordes, letras, sombras y reflejos. Las sugerencias no prueban exclusividad: revisar ambas máscaras y el fondo antes de guardar. Cada ventana HSV mantiene parámetros independientes de área mínima, área máxima (% de captura), dimensión mínima, saturación y confianza. `max_aspect_ratio` y `ambiguity_ratio` se ajustan en JSON. Los parámetros temporales siguen en `tracking`.

Los contornos aceptados se muestran en verde y los rechazados en rojo, con ID, área, confianza y motivo. La confianza es cobertura rectangular multiplicada por pureza de la región, **no una probabilidad de identificación**. Las máscaras superpuestas invalidan el contorno completo; candidatos comparables del mismo color se consideran ambiguos. Un objeto real del entorno que cumpla todos los criterios aún puede confundirse con un módulo.

**D** oculta/restaura máscaras y detalles de contornos; `--no-gui` evita las ventanas. **F3** oculta/restaura el diagnóstico de Godot; F2 sigue alternando MOUSE/EXTERNAL. Los contadores `#` muestran transformaciones efectivamente aplicadas por ID, no cantidad de paquetes.

Para rastrear un problema sin generar un mensaje por frame en consola:

```powershell
python detector.py --trace artifacts\detecciones.jsonl
```

El archivo JSONL opcional registra configuración inicial, decisiones de candidatos por fotograma, observaciones aceptadas por el seguimiento y módulos efectivamente enviados con secuencia. Puede crecer durante sesiones largas; activarlo durante una prueba breve. No guarda imágenes. Para una captura local explícita existe `--snapshot`. Los mensajes normales de métricas aparecen cada 2 segundos (`--log-interval 0` los desactiva). Godot mantiene contadores y última aplicación por módulo; `ExternalPlatformReceiver.trace_updates=true` habilita un historial de las últimas 120 aplicaciones, sin imprimirlas en cada frame.

La ventana principal muestra la imagen, contornos, centros, IDs, ángulos, LIVE/HOLD/LOST, FPS de procesamiento y estado de envío UDP. La vista de máscaras muestra verde a la izquierda y azul a la derecha. Los centros/ángulos dibujados son los valores filtrados que se transmiten; los contornos corresponden a candidatos de la imagen actual.

La indicación `UDP TX` confirma únicamente que el sistema operativo aceptó el datagrama. UDP no tiene ACK en este protocolo; comprobar recepción en el HUD de Godot. No se transmiten ni guardan imágenes de cámara por defecto. El argumento opcional `--snapshot` guarda un único frame local sólo si se lo solicita expresamente.

## Cámara

- Selección verificada el 2026-10-30 con DirectShow: **0 = Integrated Webcam**, **1 = T803E (Windows Virtual Camera)** y **2 = REDRAGON Live Camera**. `vision/config.json` usa **2**, la Redragon USB (VID 0C45 / PID 636B). Se verificó apertura, captura continua y cierre normal. Resolución de trabajo conservada: 640×480; no se probó 1080p en esta comprobación.
- `python -m vision.list_cameras` enumera nombres, índices y rutas DirectShow usando Windows y la biblioteca estándar, sin dependencias adicionales. El orden puede cambiar al conectar dispositivos: volver a comprobarlo en ese caso. Los ejemplos sin `--camera` respetan el JSON; ese argumento lo reemplaza.
- Índice configurable con `--camera 0`, `--camera 1`, etc.
- Inicio: 640×480, objetivo 30 FPS; el controlador puede negociar otros valores o entregar menos frames. El programa informa el tamaño real y FPS medidos en sus reportes.
- Backend predeterminado: DirectShow (`--backend dshow`); alternativas `msmf` y `auto`.
- `python detector.py --probe-camera` prueba la cámara configurada durante un máximo lógico de cinco segundos, sin GUI, UDP ni guardado de imágenes.
- La captura vive en un proceso separado, con un único frame compartido. La lectura del padre no espera un lock ocupado y no acumula una cola de imágenes. Se limita el sondeo de backends que devuelven frames almacenados inmediatamente.
- Errores de apertura, lectura o desconexión se muestran y disparan reintentos. El watchdog permite hasta 8 s de arranque y 2.5 s de lectura sin progreso; son configurables. Los frames vencidos dejan de ser detecciones nuevas.
- El cierre solicita salida y liberación de `VideoCapture`; si `open/read` queda bloqueado se termina el proceso de cámara. El reporte distingue cierre normal, reinicios y cierres forzados. Esto se probó con controladores falsos bloqueados y con MSMF real sin frames. Desenchufar físicamente cada modelo de webcam requiere prueba presencial.
- `mirror=false` por defecto. Si se activa en JSON, se normaliza respecto de la imagen espejada que muestra el detector.

## Reconocimiento y seguimiento

Se convierte BGR a HSV, se aplica `inRange`, apertura/cierre morfológico, contornos externos y filtros de área mínima, área máxima y ocupación del rectángulo. El centro usa momentos del contorno. La orientación usa el eje largo del rectángulo mínimo de OpenCV; no depende de las convenciones de ancho/alto/ángulo devueltas por `minAreaRect`.

Cada color tiene un ID fijo; se admite **una pieza por color**. No superponer rangos HSV. Iluminación, reflejos, sombras u objetos del fondo del mismo color pueden producir falsos candidatos: esta etapa no resuelve identidad visual general.

El seguimiento requiere tres observaciones consistentes para adquirir/re-adquirir un módulo. Luego prioriza el candidato cercano al último centro observado, no simplemente el contorno mayor. Usa límites de salto y velocidad, EMA moderado de posición y ángulo y rechazo de saltos angulares. El ancla de asociación usa la última observación, para que el retraso del suavizado no rechace movimiento válido.

Durante una pérdida breve de hasta **150 ms**, HOLD conserva exactamente la última pose filtrada: **no extrapola ni inventa posiciones**. Después envía `visible=false` con esa misma pose. Antes de la primera detección confirmada omite el módulo; no inventa una posición inicial. Al salir envía un último estado no visible; si ese datagrama se pierde, el watchdog ya existente de Godot detiene la plataforma.

## Orientación y geometría

Una pieza alargada reconocida sólo por color tiene un eje, no una dirección única: su orientación es ambigua **módulo 180°**. Una pieza cuadrada o simétrica puede ser aún más ambigua. En piezas casi cuadradas se conserva el último ángulo aceptado para reducir saltos. No se garantiza una rotación única de 360° ni el sentido físico “delante/atrás”. En formas irregulares, el eje del rectángulo envolvente es una aproximación y puede cambiar con una oclusión.

El detector nunca reconstruye formas ni envía ancho, alto, escala, contornos o vértices a Godot. Las piezas físicas pueden tener distintas geometrías; éstas continúan definidas en las escenas.

`vision/detection.py` expone el contrato `Detector.detect -> DetectionBatch/Observation`. Un futuro adaptador ArUco puede reemplazar ColorDetector y mapear marcadores a los mismos IDs, usando `orientation_period=360` cuando haya una dirección fiable. No requiere cambiar el protocolo, el receptor, el combate ni la física. ArUco no está implementado en esta etapa.

## Protocolo existente, sin cambios

```json
{"version":1,"sequence":100,"modules":[{"id":1,"x":0.35,"y":0.55,"angle":15.0,"visible":true}]}
```

Destino: **127.0.0.1:5005**, JSON UTF-8; límite 4096 bytes (normalmente unos pocos cientos con dos módulos y diagnóstico). Secuencia entera creciente iniciada con el reloj monotónico local, para poder reiniciar el detector. Ejecutar sólo un emisor por vez: no usar simultáneamente el simulador anterior y el detector.

X/Y se normalizan con respecto a la imagen de captura: `centro_x/(ancho-1)` y `centro_y/(alto-1)`, limitados a [0,1]. Y aumenta hacia abajo. El ángulo se envía en grados en [−180,180), positivo horario en coordenadas de imagen. Godot convierte estas coordenadas a su rectángulo de arena configurado y mantiene su propio suavizado/límites físicos.

Lo anterior describe CAMERA, que conserva la normalización simple. PROJECTOR incorpora homografía de posición y orientación; consultar [PROJECTOR_GUIDE.md](PROJECTOR_GUIDE.md). No hay calibración óptica de lente ni correspondencia métrica en milímetros; la primera validación física sobre pared está pendiente.

## Pruebas reproducibles

Con `--report ruta.json` se guardan tiempos de lectura, procesamiento OpenCV, antigüedad del frame, frecuencia de captura/envío, reinicios del proceso y estado de cada módulo. `--log-interval 2` emite métricas cada dos segundos; usar 0 para desactivarlas. No imprime un mensaje por frame. El HUD de Godot muestra frecuencia recibida y aplicada, secuencia y edades de entradas por módulo.

El emisor conserva `version`, `sequence` y `modules` y agrega dos campos opcionales de raíz: `sent_unix_ms` y `source_age_ms`. Los campos de cada módulo no cambiaron. El receptor admite clientes v1 anteriores sin ellos; cuando están presentes rechaza paquetes de más de 350 ms y frames de más de 250 ms. Estos plazos y las zonas muertas subpíxel se configuran en el receptor. Los clientes anteriores sólo permiten medir edad desde el desencolado local. Ver el informe para unidades y límites de las medidas.

```powershell
python -m unittest discover -s tests -v
python -m tests.gui_smoke
python detector.py --synthetic --no-gui --no-udp --duration 5
python detector.py --synthetic --no-gui --duration 8 --report artifacts/vision_sender.json
```

`--synthetic` genera imágenes BGR con dos piezas de formas distintas y las hace pasar por el detector y el seguimiento reales. Nunca abre una cámara. La última orden sí envía poses a Godot; usar EXTERNAL para probarla. `--duration` permite cerrar automáticamente. Las pruebas unitarias de cámara usan dispositivos falsos, separadas de la comprobación física.

Referencias oficiales: [HSV/inRange](https://docs.opencv.org/4.x/da/d97/tutorial_threshold_inRange.html), [contornos/minAreaRect](https://docs.opencv.org/4.x/d3/dc0/group__imgproc__shape.html), [HighGUI/trackbars](https://docs.opencv.org/4.x/d7/dfc/group__highgui.html), [distribución opencv-python](https://pypi.org/project/opencv-python/).
