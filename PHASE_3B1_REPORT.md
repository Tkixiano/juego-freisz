# Fase 3B.1 — segmentación y representación multimaterial

Implementación exclusivamente sintética/offline, con verde, azul y naranja.
No se abrió ningún dispositivo físico ni se invocó VideoCapture sobre cámaras.
Los tests de captura usaron fábricas/targets falsos. No se usó proyector.
No hay rebote físico, one-way nuevo ni conexión de materiales con UDP o combate.

## Arquitectura

`MaterialStructures` compone los módulos existentes: `StructureSegmenter` →
`StructureTracker` → `ContractExporter/build_contract` → ledger de snapshots
completos. Añade partición exclusiva, seguimiento regional y publicación completa
confirmada. Mantiene separados ID lógico/época y regiones con sus propios IDs,
propietarios, materiales, contornos, agujeros y revisiones.

El segmentador anterior conserva su comportamiento por defecto. La opción
multimaterial mantiene máscaras HSV crudas, rechaza conflictos sin asignarles
otro color, filtra ruido y obtiene la unión. Conserva conectividad por esquina,
concavidades y agujeros. Las partes rectangulares son una partición exacta de
celdas de la silueta, **no bounding boxes que sustituyan su forma**.

La publicación conserva la última estructura y partición válidas durante
confirmación o rechazo. No se exporta una silueta nueva junto con materiales
viejos. El tracker anterior sigue resolviendo MERGE/SPLIT; las regiones conservan
IDs al cambiar propietario solo ante evidencia mutuamente única.

Contrato y reglas completas en [MATERIAL_CONTRACT_V1.md](MATERIAL_CONTRACT_V1.md).
Se conserva `contract_version=1` y se agrega `material_contract_version=1`.
El protocolo UDP 3A no cambió. La configuración HSV anterior tampoco se sobrescribió.

## Archivos

Producción existente modificada:

* `vision/structure_segmentation.py`: modo exclusivo opcional y máscaras de
  material/conflicto; defaults anteriores conservados.
* `vision/offline_replay.py`: helper compartido de épocas/revisiones; la huella
  incluye materiales solo cuando la extensión está presente. Formato antiguo intacto.
* `vision/config.py`: validación de color reutilizable y timeout de bootstrap
  compatible con archivos antiguos.
* `vision/camera.py` y `capture_worker.py`: corrección medida de arranque de
  procesos frente a apertura/lectura del driver; no se cambió UDP.

Producción nueva:

* `vision/material_config.py`, `materials_config.json`: perfil independiente de tres colores.
* `vision/material_structures.py`: partición, IDs de región, confirmación y snapshots.
* `vision/material_synthetic.py`: veinte escenarios con máscaras de referencia.
* `vision/material_lab.py`: diagnóstico/calibración sobre imágenes sintéticas o archivos.
* `juegofrei/scripts/geometry/MaterialGeometryValidator.gd`: validación offline aditiva.
* `MaterialRepresentationLab.gd` y `scenes/MaterialRepresentationLab.tscn`: dibujo de
  ejemplos, sin cuerpos físicos ni sockets.

Pruebas nuevas: `test_material_structures.py`, `test_capture_bootstrap.py`,
`capture_bootstrap_fakes.py`, `probe_capture_timeouts.py`, `material_gui_smoke.py`,
`benchmark_materials.py`; y los scripts `MaterialGeometryValidation.gd`,
`MaterialGeometryHeadless.gd`, `Phase3B1OriginalRegression.gd`, sus `.uid` y los
fixtures generados. Se modificaron dos arneses anteriores: `tests/test_vision.py`
(espera explícita de bootstrap) y `CompoundGeometryValidation.gd` (muestreo físico).

Evidencias en `artifacts/phase3b1/`; JSON de validación en `juegofrei/validation/`.
La comparación de 83 archivos anteriores detectó solamente los cinco módulos
Python indicados. Combate, gravedad, menús, jugadores, plataformas y protocolos
anteriores no tienen modificaciones de producción.

## HSV y ejecución

Perfil: `vision/materials_config.json`, independiente de `vision/config.json`.

| Color | H inicial | S inicial | V inicial | Área mínima |
|---|---:|---:|---:|---:|
| Verde | 35–85 | 90–255 | 55–255 | 12 px |
| Azul | 95–135 | 100–255 | 55–255 | 12 px |
| Naranja | 5–25 | 120–255 | 65–255 | 12 px |

La saturación efectiva mínima también respeta `min_saturation`. Los rangos
requieren calibración real futura; iluminación, reflejos y colores cercanos
pueden cambiar la clasificación. Rangos solapados producen píxeles excluidos,
no una elección arbitraria ni dos materiales superpuestos.

Desde la raíz:

```powershell
python -m vision.material_lab --calibrate
python -m vision.material_lab --calibrate --image ruta\muestra.png
```

No abren cámara: usan el escenario sintético o la imagen indicada. **1/2/3**
selecciona verde/azul/naranja, los deslizadores ajustan HSV/área/saturación,
arrastrar una ROI calcula estadísticas; **A** aplica explícitamente la sugerencia,
**S** guarda el perfil independiente, **L** lo recarga y reinicia el seguimiento,
**Q** cierra. Las estadísticas no garantizan una calibración correcta. No se permite
guardar por accidente sobre el archivo legacy `vision/config.json`.

Ejemplo offline completo, sin ventanas ni red:

```powershell
python -m vision.material_lab --headless --scenario 11_split --export artifacts/phase3b1/material_split_example.json
```

En Godot abrir `res://scenes/MaterialRepresentationLab.tscn` y ejecutar la escena
actual. Cada recuadro representa un escenario independiente, por lo que sus IDs
pertenecen a instancias de seguimiento diferentes. El laboratorio solo dibuja
partes/IDs: no aplica materiales a la física.

## Exactitud e identidad

Se ejecutaron los veinte casos solicitados: colores individuales, separados,
uniones verde/naranja y azul/naranja, tres materiales, verdes unidos, tres
regiones verdes, MERGE/SPLIT multimaterial, agujeros, concavidad, esquina,
región de un píxel de espesor, ruido, tonos cercanos, iluminación, pérdida breve
y reaparición. Referencias independientes en mapas de etiquetas, no deducidas
del resultado del detector.

En los veinte estados finales: **IoU 1,0**, **cero píxeles mal clasificados**,
**cero píxeles superpuestos** y conservación exacta del área en los mapas de
referencia. Godot comprobó las áreas por material y la cobertura poligonal;
no se rellenaron agujeros. Estos resultados son de imágenes sintéticas, no de
una pared ni de condiciones ópticas reales.

* Se conservaron los dos IDs regionales verde/azul durante MERGE y SPLIT.
* Cinco ciclos adicionales conservaron esos IDs: **5 MERGE y 5 SPLIT**;
  las épocas de las estructuras recuperadas llegaron a 6.
* Movimiento sin cambio de silueta conserva IDs/revisiones geométricas.
* Pérdida breve de dos frames conserva los tres IDs; tras retirada confirmada
  y reaparición se generan IDs nuevos, sin reutilización insegura.
* Uniones/separaciones ambiguas del mismo material generan nuevas identidades
  regionales y un evento explícito de ambigüedad.
* Una reclasificación de un frame no cambia la partición publicada; cambiar
  material/límite de forma confirmada incrementa la revisión de estructura.

Resultados detallados de cada escenario y áreas en `scenarios.json`.

## Problemas encontrados y corregidos

**Timeouts de Fase 3A:** un probe sin cámaras midió entrada del hijo a 1,929 s,
NumPy listo a 4,947 s y OpenCV a **6,048 s**. El watchdog anterior de 4 s podía
matarlo antes de publicar su primer heartbeat. Tres reproducciones no entregaron
ningún frame y reiniciaron alrededor de 4,1–4,2 s. Una ventana diagnóstica más
larga permitió obtener el primer frame falso a 5,960 s.

Se separó bootstrap Python/imports (15 s configurables) de apertura y lectura.
El worker publica su fase antes de cargar bibliotecas pesadas y registra las
fases/tiempos en diagnóstico. Se conservaron los plazos nativos. El cierre sigue
acotado con terminación del hijo si está bloqueado.

La fixture de los cinco tests anteriores ahora espera el bootstrap explícito
antes de medir operaciones nativas. **No se aumentaron sus límites de apertura
4 s, stall 0,5 s ni cierre menor a 2 s.** Dos pruebas nuevas verifican que el
bootstrap sin progreso siga terminando y que no consuma el plazo nativo de
apertura. Pasaron 7/7 en la clase ampliada, luego las regresiones completas de
145/145 y 147/147. No se afirma una prueba de webcam real.

**Agujero con centroide fraccionario:** Godot informó área 11.999,999619 frente
a intersección 12.000,000916 px², excediendo el epsilon 0,001 del validador.
Se corrigió mediante un ancla entera local en el exportador multimaterial,
ajustando todos los vértices del mismo modo. No cambió ningún borde global ni
se relajó el validador anterior. El caso pasó después con error de área cero.

**Regresión 1C:** el test antiguo acumulaba 2–3 ticks físicos entre muestras al
esperar un frame renderizado. Con render a 30 FPS observó 3 px por muestra,
pero **1,5 px/tick**, 60/60 muestras apoyadas y penetración cero. Se corrigió
solo el muestreo a cada tick; se conservó el umbral `<3` y se agregó una
aserción de cadencia. La suite pasó **110/110** a 30 FPS y en la repetición normal.

**Configuración y datos inválidos:** perfiles malformados se rechazan sin cerrar
la UI; se protege el perfil legacy. Snapshots publicados no permiten modificar
el estado interno del tracker. Se rechazan regiones vacías, versiones/tipos
incorrectos, solapamientos, partes fuera de silueta y coordenadas no finitas.

## Regresiones

| Suite | Resultado comprobado |
|---|---:|
| Python completa, primera pasada | 145/145 |
| Python completa ampliada | 147/147 |
| Multimaterial después de la caché | 14/14, incluyendo los veinte escenarios |
| Contratos de material Godot | 160/160 headless y MCP final |
| Calibración HSV con controles OpenCV reales e imagen sintética | 12/12 |
| Juego original, regresión gráfica general | 235/235 |
| Selección/personajes gráfica | 111/111 |
| UDP anterior dentro del juego | 37/37 |
| Fase 2B headless / Fase 2A | 92/92 · 93/93 |
| Fase 1A / Fase 1C corregida / Fase 1D | 92/92 · 110/110 · 127/127 |
| Protocolo UDP 3A sin modificaciones | 160/160 |

Los logs de los intentos fallidos se conservan. Hubo un bloqueo de escritura en
un directorio temporal del aislamiento; la repetición autorizada pasó. El MCP
local dejó de escuchar durante el cierre de evidencias; se recuperó el servicio
desde su paquete 3.2.5 ya en caché, sin descargas, y se reconectó al editor.
La recuperación UI no respondió; se usó el ejecutable existente. No se modificó
el plugin ni la configuración del proyecto para recuperarlo.

## Rendimiento y límites

Se midió una imagen fija de 640×480 con tres materiales y 120 iteraciones,
después de diez de calentamiento. No incluye captura, red, render ni colisiones;
**no es una medición de FPS sostenidos del juego**.

La primera medición con ocho hilos OpenCV dio media 476,61 ms, P50 457,18 ms,
P95 683,42 ms y P99 773,63 ms. Con un hilo, siguiendo la política del detector
existente, dio media 375,61 ms y P99 645,71 ms.

El perfilado identificó reconstrucción repetida de los contornos de material.
Se agregó una caché acotada por máscara exacta recortada y verificada, que
reutiliza el constructor de Fase 1C y rebasa sus resultados. No usa bounding boxes
como colisiones ni simplificación que cambie áreas. La repetición de exactitud
e identidad pasó después.

Con la caché y un hilo: **media 117,36 ms; P50 107,49 ms; P95 160,77 ms;
P99 187,10 ms**. Un build de silueta general, un build de geometría regional
compartida por las tres formas iguales y 383 aciertos de caché en ese ensayo.
La repetición dio **media 145,85 ms; P50 140,17 ms; P95 197,21 ms;
P99 208,39 ms**, también sin errores. Los percentiles de cada ejecución se
mantienen separados; no se promedian como una sola medición.
El rendimiento continúa por encima de 33 ms/frame en esta máquina/entorno;
no se declara un detector multimaterial a 30 FPS.

Los benchmarks y repeticiones están en `benchmark_640*.json`. Antes de conectar
con física conviene perfilar segmentación/asignaciones por ROI y escenarios
móviles/irregulares, incluyendo caché fría y límites máximos. No se promete que
la ganancia de una imagen fija se conserve con cambios continuos de topología.

## Preparación para Fase 3B.2

Quedan listos los materiales, regiones, pertenencia, geometrías y revisiones,
con ejemplos y validación Godot. La fase siguiente debería implementar y probar
la semántica física por región y sus normales, tratando contactos entre materiales
sin duplicar la colisión general. Debe conservar transacciones, soporte y rechazo
de penetraciones del backend existente.

También requiere mejorar el presupuesto temporal antes de una integración de
tiempo real, decidir el tratamiento de precisión tras homografía/subpíxeles y
validar calibración real cuando haya hardware autorizado. La extensión y sus
IDs deberán validarse antes de cualquier futura conexión UDP; no se realizó aquí.

**Fase 3B.1 finalizada. No se avanzó a Fase 3B.2.**
