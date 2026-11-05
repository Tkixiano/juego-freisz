# Calibración cámara → proyección

Implementado y probado con imágenes sintéticas, ventanas reales y Godot 4.6.3. **Todavía no se validó físicamente con proyector y webcam sobre una pared.** El equipo detectaba una sola pantalla 1366×768 durante el desarrollo. No se creó una homografía física de ejemplo en la ruta predeterminada: debe obtenerse con el montaje real.

## 1. Preparar la salida

- Conectar el proyector por HDMI y seleccionar **Extender** en Windows. Identificar su número en la lista de monitores de la escena de calibración: los índices de Godot empiezan en 0 y pueden diferir de los números mostrados por Windows.
- Fijar cámara, proyector y superficie plana. Conservar enfoque, zoom, keystone, resolución, orientación y ubicación durante calibración y partida. Las piezas deben estar en el mismo plano calibrado; objetos alejados de la pared introducen paralaje.
- Cerrar el detector normal para liberar la Redragon. Conserva su configuración en `vision/config.json`: DirectShow índice 2, captura solicitada 640×480, sin espejo. Verificar índices con `python -m vision.list_cameras` si cambian los dispositivos USB.
- No cambiar la calibración HSV para realizar la geométrica. La pantalla blanca de calibración y los marcadores no controlan plataformas: este proceso no envía UDP.

## 2. Iniciar calibración

Desde la raíz del proyecto:

```powershell
cd "C:\godot 4.6\juego frei"
python -m vision.projector_calibration --screen 1
```

También: `CalibrateProjector.cmd --screen 1`. Cambiar 1 por el índice real; actualmente solo existe 0. El lanzador abre la escena independiente `ProjectionCalibration.tscn` y la cámara. Usa `--godot "RUTA\godot.exe"` si el ejecutable cambia.

En Godot se puede seleccionar el monitor y mostrar el patrón en ventana o pantalla completa. **Para calibración física usar pantalla completa y luego el mismo monitor y aspecto para jugar.** Vista previa es una herramienta de desarrollo: su encuadre no equivale al de pantalla completa. Si se cambia de monitor, tamaño o modo de salida después de capturar, repetir con R y SPACE antes de guardar. La cámara y el panel del operador deben permanecer en la pantalla de la notebook; el patrón ocupa el proyector.

Los ocho marcadores ArUco DICT_4X4_50 tienen IDs exclusivos:

| Uso | IDs | Centros en el lienzo lógico |
|---|---|---|
| Ajuste | 10, 11, 12, 13 | (180,140), (1100,140), (1100,580), (180,580) |
| Verificación independiente | 14, 15, 16, 17 | (640,230), (880,360), (640,490), (400,360) |

El cuadrilátero de los centros 10–13 delimita el dominio calibrado. El rectángulo gris muestra los límites de los centros de plataformas: x=150…1130, y=180…520. La zona útil para controlar módulos es la **intersección** de ambas áreas. Fuera de ella se detiene el seguimiento; no se extrapolan coordenadas ni se desplazan a un borde artificialmente.

## 3. Detectar y confirmar

1. Encuadrar los ocho marcadores enteros en la webcam, incluidos sus márgenes blancos.
2. **SPACE** congela el fotograma y detecta referencias. Se requieren los ocho IDs sin duplicados. El centro automático es la intersección proyectiva de diagonales del marcador, no el promedio de sus esquinas.
3. Revisar el diagnóstico: RMS y máximo del ajuste y de los puntos independientes. **R** descarta el candidato y vuelve a captura en vivo para repetir.
4. Si falla la detección automática, **M** congela la imagen e inicia selección manual. Hacer clic en el centro de los marcadores en orden **10,11,12,13,14,15,16,17**. Los cuatro últimos siguen siendo verificadores, no puntos del ajuste.
5. **S** confirma y guarda solo un candidato válido. **L** carga y revalida el archivo guardado y comprueba su compatibilidad con la captura. **Q** o Escape cierra y libera la cámara. Cancelar o repetir **antes de S** deja intacto el archivo anterior; S ya es una confirmación.

Se usa `cv2.findHomography` con RANSAC y se exige que todos los puntos de ajuste sean consistentes. Se rechazan distribuciones pobres/colineales, puntos repetidos, matriz singular o mal condicionada, horizonte atravesando el área, ejes invertidos inesperados y errores excesivos. Espejo de captura explícito admite la inversión correspondiente; cambiarlo invalida el archivo anterior.

Límites actuales: error máximo de ajuste ≤3 px; RMS independiente ≤3 px; máximo independiente ≤4 px. **Las unidades son píxeles del lienzo lógico proyectado 1280×720**, no necesariamente píxeles nativos HDMI. Patrón y juego usan el mismo lienzo, mantienen aspecto y aplican las mismas bandas negras. En una salida 1920×1080 de aspecto 16:9, un píxel lógico equivale a 1,5 píxeles nativos. No se anuncia error físico medido sin hacer la prueba real.

## 4. Archivo de homografía

Predeterminado: `vision/projector_calibration.json`. Independiente del HSV. Contiene versión, patrón, resolución real de captura, resolución lógica de proyección, matriz 3×3, correspondencias de ajuste/verificación, errores recalculados, índice/backend/espejo de cámara y fecha UTC. El guardado es atómico. `--output RUTA` selecciona otro archivo.

Al cargar no se confía en los errores almacenados: se vuelven a calcular. Cambiar captura, resolución lógica, índice, backend o espejo exige recalibrar. Mover cámara/proyector, cambiar monitor, zoom, keystone, resolución física o posición de ventana también exige recalibrar, aunque el software no puede detectar todos esos cambios físicos automáticamente. Reabrir una calibración no sustituye una verificación visual en el montaje real.

## 5. Jugar con coordenadas proyectadas

Cerrar la calibración. Iniciar el juego en **el mismo proyector y pantalla completa**:

```powershell
& "C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe" --path "C:\godot 4.6\juego frei\juegofrei" --screen 1 --fullscreen
```

En otra terminal:

```powershell
python detector.py --coordinates PROJECTOR --calibration vision/projector_calibration.json
```

Iniciar partida y seleccionar **EXTERNAL con F2**. El panel debe indicar **Coordenadas PROJECTOR**. F3 oculta el diagnóstico. El modo MOUSE sigue disponible.

El centro y un eje local asociado a la orientación se transforman mediante `cv2.perspectiveTransform`. La orientación se recalcula en píxeles proyectados; no se reutiliza el ángulo de cámara. Permanece la ambigüedad de 180° de piezas simétricas.

PROJECTOR usa UDP v2 explícito, x/y normalizados por 1279/719 sobre todo el lienzo. Godot solo convierte a píxeles y llama al PlatformManager existente: no aplica una segunda homografía ni la expansión del modo CAMERA. Si un centro queda fuera de los límites físicos de movimiento, lo marca no detectado y congela; no altera geometría.

Para volver al flujo anterior:

```powershell
python detector.py --coordinates CAMERA
```

CAMERA sigue enviando UDP v1 y conservando la normalización hacia el rectángulo de arena anterior. Los emisores v1 sin campo de coordenadas siguen siendo CAMERA. Godot rechaza v2 sin metadatos completos, v1 etiquetado PROJECTOR y resoluciones incompatibles.

## 6. Desarrollo sin proyector

```powershell
python -m vision.projector_calibration --generate-pattern
python -m vision.projector_calibration --no-launch --image juegofrei/calibration/projector_pattern.png --output artifacts/demo_projection.json
```

La segunda orden permite SPACE/S/R/L/Q sobre una imagen, sin abrir webcam ni requerir otro monitor. **No usar ese archivo como calibración física.** También puede abrirse la escena de calibración desde Godot y usar la vista previa. `--no-launch` se usa cuando el patrón ya está abierto o para pruebas de imagen.

Pruebas repetibles:

```powershell
python -m unittest tests.test_vision tests.test_color_isolation tests.test_projection -v
python -m tests.projector_gui_smoke
python -m tests.gui_smoke
```

OpenCV instalado tiene `cv2.aruco`; no fue necesario agregar dependencias a requirements.txt. No instalar a la vez paquetes diferentes que proporcionen cv2.

## 7. Primera prueba sobre pared — pendiente

1. Calibrar con pared plana y referencias visibles; registrar RMS/MAX independientes.
2. Con el juego en el mismo modo de salida, colocar cada módulo sobre varios puntos conocidos dentro de la zona útil. Comparar centro físico y centro de plataforma.
3. Probar verde solo, azul solo, ambos, rotación, oclusión y recuperación. Revisar ID, estado y contador de aplicaciones.
4. Verificar que los colores del juego proyectado y la iluminación no activen falsos módulos; recalibrar HSV bajo esas condiciones.
5. Probar colisiones y combate sobre plataformas controladas físicamente. Las pruebas actuales de software no sustituyen esta validación.

No se implementó corrección de distorsión de lente. Una lente con distorsión apreciable o una pared no plana puede no superar los verificadores; no relajar límites para ocultarlo. Las piezas deben permanecer en el plano calibrado. La proyección de colores del propio juego puede interferir con seguimiento por color: pendiente validar y, si es necesario en otra etapa, aislar iluminación/colores o cambiar identificación.

Referencias de API: [OpenCV ArUco](https://docs.opencv.org/4.13.0/d5/dae/tutorial_aruco_detection.html), [homografía OpenCV](https://docs.opencv.org/4.x/d7/dff/tutorial_feature_homography.html), [opciones de ventana de Godot 4.6](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html).
