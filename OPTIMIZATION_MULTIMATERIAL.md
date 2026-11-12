# Optimización multimaterial — informe

Fecha: 8 de noviembre de 2026. Godot 4.6.3. Solo imágenes, contratos y transmisiones sintéticos.



## Resultado y alcance

Se redujo trabajo repetido sin cambiar HSV, siluetas, agujeros, IDs/épocas, materiales, gravedad, controles ni reglas de combate. No se sustituyen los contratos ni los protocolos. Las mejoras son medibles; **no se alcanzan 30 Hz ni 60 FPS con todas las cargas de estrés**. No se utilizó cámara ni proyector.



## Línea base y metodología

Benchmarks nuevos y reproducibles: `python -m tests.benchmark_pipeline --frames 40 --output ruta.json`; resolución 640×480, OpenCV con un hilo, 8 fotogramas de calentamiento y 40 medidos por cantidad. El caso A/B mueve los objetos cada 4 fotogramas; también se midió movimiento en cada fotograma (`--motion-every 1`) y cambios de silueta (`--shape-change`). La generación de imágenes queda fuera del tiempo de procesamiento en ambos casos.

La línea base se guardó antes de editar producción. Se añadieron mediciones aisladas finales; no es un ensayo de laboratorio con CPU/frecuencias/sistema operativo bloqueados. Las cargas iniciales más grandes pudieron coincidir parcialmente con el comienzo del benchmark headless: las razones A/B son orientativas, no garantías universales. Los JSON conservan muestras y condiciones.

En Python, 64 objetos separados son 64 estructuras. En Godot/UDP, el caso de 64 regiones se reparte entre 32 estructuras, respetando el límite vigente de transporte. Los corpus no son intercambiables entre runtimes, pero cada comparación A/B reutiliza el mismo corpus.



## Python: procesamiento completo

| Regiones | Media antes ms | Media después ms | Después P50 / P95 / P99 ms | FPS equivalentes | Media movimiento continuo ms |
|---|---|---|---|---|---|
| 1 | 36.87 | 17.72 | 8.06 / 45.38 / 46.64 | 56.4 | 31.74 |
| 4 | 63.84 | 19.34 | 12.70 / 40.94 / 47.53 | 51.7 | 34.81 |
| 8 | 125.97 | 30.10 | 22.84 / 58.24 / 59.04 | 33.2 | 43.05 |
| 16 | 227.03 | 39.51 | 32.01 / 65.99 / 77.45 | 25.3 | 53.63 |
| 32 | 576.54 | 67.87 | 65.20 / 99.22 / 101.75 | 14.7 | 86.58 |
| 64 | 1426.84 | 147.59 | 141.33 / 205.06 / 293.05 | 6.8 | 154.82 |



Los FPS equivalentes son 1000/media de CPU del pipeline, **no FPS de captura, del juego o de presentación**. El movimiento continuo evita atribuir a una cámara real el beneficio de imágenes idénticas. La caché de imagen exacta probablemente tendrá menos aciertos con ruido de una webcam.

Desglose completo antes/después con P50/P95/P99: [python_stages.csv](artifacts/optimization/python_stages.csv). HSV, máscaras y componentes se cronometran con los métodos reales; seguimiento y construcción incluyen sus llamadas internas, por lo que **no deben sumarse todas las filas**. Algunas etapas solo tienen muestras cuando se invocan. Los contornos pueden costar cero tras el calentamiento porque se reutilizan siluetas exactamente iguales; no se eliminó su extracción en geometrías nuevas.



## Optimizaciones aplicadas

1. Componentes por material procesados en el recorte exacto de cada estructura; se reconstruyen máscaras globales para conservar el contrato y el seguimiento. El recorte limita trabajo, no sustituye la silueta.

2. Solapamientos entre pistas y observaciones limitados a la intersección de sus límites exactos; áreas precalculadas y mapas de distancia reutilizados dentro del mismo ciclo. Se mantienen umbrales y correspondencias conservadoras.

3. Caché de segmentación exclusivamente para imágenes idénticas y perfil HSV/configuración idénticos. Entradas/salidas independientes: modificar una máscara o una imagen no contamina la siguiente. El tipo de imagen se vuelve a comprobar.

4. Validación de contrato Python cacheada por todos los campos que esa función comprueba; invalidación por contenido, material, propietario y versión. Fallos no se cachean. Límites: 256 entradas.

5. En Godot, validación geométrica cacheada por geometría local, propietario y materiales; los metadatos, pose, confianza, seguimiento y versiones se comprueban de nuevo. Las copias devueltas son independientes. Máximo 128 entradas.

6. Se evita copiar profundamente regiones ajenas a cada collider al aplanar una estructura; el adaptador base conserva la copia propia en el límite transaccional. No se reconstruyen formas por una pose nueva.

7. El receptor puede reunir hasta dos mensajes completos y elegir el de sesión/secuencia más reciente; comprueba integridad antes de reunirlos y el contrato completo antes de publicar. Si el más reciente es inválido, prueba el anterior. Rechaza duplicados y conserva las reglas de epochs/recuperación. Es opt-in para la partida; el laboratorio conserva el comportamiento anterior por defecto.

8. Recuperación acotada del socket: presupuesto habitual 8 ms y hasta 12 ms cuando hay al menos 64 datagramas en cola. Se mantienen 128 datagramas y dos completos por ciclo. Puede aumentar un pico de lectura para evitar gastar validación en una cadena de estados viejos; no es una garantía de frame de 16,7 ms.



## Godot: validación, aplicación, física y render

La escena real fue inspeccionada y ejecutada por Godot AI MCP. El benchmark gráfico usa ambos Player existentes y ataques simultáneos, poses cambiantes y los tres materiales. Somete un estado por tick físico (hasta 60/s), más exigente que el emisor normal de 30/s. Doce ticks de calentamiento y 60 medidos por caso.

| Regiones | Preparación antes P50 ms | Después P50 / P95 / P99 ms | Protocolo después P50 / P95 / P99 ms | Formas | Penetraciones |
|---|---|---|---|---|---|
| 1 | 4.21 | 1.30 / 1.99 / 2.23 | 0.68 / 0.97 / 1.05 | 2 | 0 |
| 4 | 15.50 | 4.73 / 6.43 / 7.23 | 2.09 / 3.17 / 3.88 | 12 | 0 |
| 8 | 25.61 | 7.24 / 8.89 / 9.39 | 3.06 / 4.24 / 4.95 | 24 | 0 |
| 16 | 40.09 | 11.81 / 18.46 / 20.34 | 5.02 / 7.73 / 9.00 | 52 | 0 |
| 32 | 79.93 | 24.99 / 34.83 / 35.68 | 10.48 / 14.42 / 16.71 | 104 | 0 |
| 64 | 89.47 | 41.66 / 59.89 / 62.70 | 13.81 / 19.90 / 22.88 | 128 | 0 |



Los detalles de commit, tiempo físico informado por Godot, procesamiento, render CPU/GPU e intervalos están en [godot_stages.csv](artifacts/optimization/godot_stages.csv). Los monitores pueden repetir el último valor; no son mediciones independientes de cada tick. El intervalo de callback físico incluye pacing y catch-up; el intervalo `frame_post_draw` mide presentación del render del motor, no el refresco físico de un monitor.

La secuencia gráfica completa, que mezcla cargas pequeñas y estrés, pasó de **6.2 a 18.2 renders/s medios**. Este agregado incluye calentamiento y transiciones; no representa FPS de una partida normal. Sus pausas largas impiden declarar 60 FPS sostenidos. Las mediciones específicas por carga tienen prioridad para evaluar casos representativos.

| Regiones | Renders/s medios despues | Intervalo draw P50 / P95 / P99 ms |
|---|---|---|
| 1 | 60.1 | 16.56 / 17.57 / 17.94 |
| 4 | 60.1 | 16.72 / 18.18 / 23.12 |
| 8 | 31.4 | 33.08 / 36.94 / 38.91 |
| 16 | 5.8 | 177.04 / 218.07 / 219.06 |
| 32 | 2.7 | 369.11 / 464.83 / 472.43 |
| 64 | 1.8 | 513.43 / 726.63 / 742.82 |

Se crearon 125 conjuntos geométricos iniciales entre los seis casos; los cambios de pose posteriores no agregaron reconstrucciones. Las cantidades físicas corresponden al material: ONE_WAY usa superficies superiores y no necesariamente una forma por región.



## UDP real: carga y latencias finales

Emisor Python independiente y PacketPeerUDP real, ejecutados secuencialmente. Casos pequeños: 6 s; 32/64 regiones: 12 s; 30 Hz solicitados. Los actores se desactivan en este ensayo de carga para aislar recepción/backend; combate y personajes se verifican en pruebas separadas.

| Regiones | Comprobaciones | Recibidos / aplicados | Edad al aplicar P50 / P95 / P99 ms | Recepción P50 / P95 / P99 ms |
|---|---|---|---|---|
| 1 | 7/7 | 158 / 105 | 26.88 / 28.49 / 29.39 | 10.39 / 11.14 / 11.44 |
| 4 | 7/7 | 158 / 106 | 24.50 / 26.17 / 38.26 | 6.80 / 7.77 / 9.00 |
| 8 | 7/7 | 163 / 108 | 30.14 / 33.05 / 34.17 | 11.51 / 12.87 / 13.93 |
| 16 | 7/7 | 161 / 89 | 29.43 / 39.18 / 49.09 | 14.00 / 15.43 / 17.78 |
| 32 | 7/7 | 199 / 78 | 434.75 / 497.93 / 501.35 | 452.01 / 489.62 / 491.68 |
| 64 | 7/7 | 137 / 12 | 473.04 / 500.22 / 501.88 | 481.56 / 490.77 / 492.46 |

Ver [udp_stages.csv](artifacts/optimization/udp_stages.csv): recepción, validación, espera→commit y antigüedad al aplicar. El timestamp se genera tras preparar/validar el emisor: no incluye captura, visión ni latencia de extremo a extremo. Los percentiles de estados aplicados excluyen descartes; leerlos junto con sus contadores. No hay garantía de entrega UDP.

Comparación histórica de 3D con 32 regiones: 95 estados recibidos / 11 aplicados, edad de recepción P50 486,33 ms. El primer ensayo de esta optimización subió a 285 / 122 pero todavía tuvo P50 410,83 ms; se conserva como resultado intermedio. La tabla anterior contiene la repeticion final con el limite original de 8 ms; el ensayo a 12 ms fue descartado. Se conservan todas las iteraciones.



## Geometría e identidades

El corpus anterior se compara por hashes de los estados completos: geometrías, poses, IDs, épocas, versiones y eventos. Los seis casos de movimiento conservan sus hashes. En los 20 escenarios de topología se verifican exactamente los mismos resultados; para un fotograma de retirada se comprobó igualdad por permutación de los tres REGION_REMOVE, cuyo orden ya dependía de un conjunto sin ordenar. No se modifica el criterio de identidad para hacer pasar pruebas.

Se mantienen agujeros, concavidades, contacto por esquina, pérdida/reaparición y MERGE/SPLIT. No se redujo resolución, vértices, área mínima ni precisión; no se generaron bounding boxes físicas ni convex hulls sustitutos.



## Regresiones y pruebas nuevas

Python: **164/164**, incluidas seis regresiones nuevas de igualdad, cachés y entradas inválidas. Receptor/validador Godot: **9/9** pruebas nuevas (nuevo inválido con fallback, desorden de llegada, duplicados, límites, actualización de metadatos y propietario inválido). Prueba real de fallos: **15/15**. Todos los casos de carga deben leerse por separado en sus logs.

Suites headless repetidas: selección 92/92; dash/ataques 93/93; 1A 92/92; 1C 110/110; 1D 127/127; contrato multimaterial 160/160; física 3B.2 142/142; offline 3B.3 196/196; partida 3C 59/59; UDP 3A 160/160; integración 3D 43/43; carga/parsing sin fallos. Ejecución gráfica histórica: 235/235 generales, 111/111 selección y 37/37 UDP anterior.

La primera versión del agrupamiento no contabilizaba un duplicado recibido en el mismo lote y falló 1/15. Se corrigió el rechazo antes de agrupar; se conserva el log inicial y la repetición pasó 15/15. Los criterios no se rebajaron.



## Archivos

- `vision\material_structures.py`

- `vision\structure_segmentation.py`

- `vision\structure_tracking.py`

- `vision\structure_udp.py`

- `juegofrei\scripts\geometry\MaterialGeometryValidator.gd`

- `juegofrei\scripts\integrated\RuntimeGeometrySources.gd`

- `juegofrei\scripts\material_physics\MaterialPhysicsAdapter.gd`

- `juegofrei\scripts\structure_udp\StructureProtocol.gd`

- `juegofrei\scripts\structure_udp\StructureUdpReceiver.gd`

Nuevos: `tests/benchmark_pipeline.py`, `tests/benchmark_states.py`, `tests/test_performance_invariants.py`, `tests/summarize_optimization.py`; `validation/PerformanceValidation.gd`, `PerformanceHeadless.gd`, `ReceiverStagingHeadless.gd`; corpus, logs, CSV y JSON en `artifacts/optimization/` y `validation/`. Los scripts de ejecución secuencial están en `tmp/run_optimization_profiles.py` y `tmp/run_optimization_regressions.py`.



## Reproducción y límites

```powershell
python -m tests.benchmark_pipeline --frames 40 --output artifacts/optimization/repeat.json
python -m tests.benchmark_pipeline --frames 24 --motion-every 1 --output artifacts/optimization/continuous_repeat.json
python -m unittest discover -s tests -p "test_*.py"
python tmp/run_optimization_regressions.py
python tmp/run_optimization_profiles.py
python -m tests.summarize_optimization
```

Los perfiles y las regresiones deben ejecutarse por separado para evitar competencia de CPU. El script de resumen usa archivos before/after ya guardados; no altera las medidas.

Persisten costes por máscaras globales necesarias para seguimiento, copias seguras, serialización repetida y validación/colisiones de muchas regiones. El peor caso de 64 regiones sigue siendo estrés extremo. Las cachés están acotadas pero añaden memoria; la caché de imagen completa tiene baja utilidad si cada píxel cambia por ruido. Los picos de validación no son interrumpibles por el presupuesto de lectura.

Antes de pruebas físicas: repetir cargas representativas durante varios minutos en el hardware final, medir con ruido/oclusiones/iluminación controlados, vigilar memoria y colas, y validar límites de velocidad y apoyo con dos jugadores. No abrir captura ni proyector hasta autorizar esa etapa. El piso sigue dependiendo de EMPTY confirmado; STALE/ERROR preservan la última física válida. No se avanza automáticamente de fase.

## Prueba grafica representativa con UDP real

Resultado 15/15. En 1033 renders, media **59.94 renders/s**; intervalo P50/P95/P99 **16.63 / 19.41 / 22.89 ms**. Edad envio preparado -> aplicacion P50/P95/P99 **21.14 / 34.10 / 35.78 ms**. Ensayo de unos 17 segundos con tres materiales, dos jugadores y fallos programados; no certifica rendimiento sostenido durante minutos ni uso de una webcam.

## Cambios de silueta en cada fotograma

P50/P95/P99 del pipeline: 4: 58.53/74.76/75.41 ms; 16: 64.79/75.80/79.47 ms. Sin errores. Estas cargas no alcanzan 30 Hz; sus etapas completas figuran en python_stages.csv como shape_changes.

## Estado final

Partida abierta mediante MCP en modo UDP, dos jugadores, SCENE_ACTIVE, sin pausa y sin errores en su log. Se deja un emisor sintetico finito de tres ciclos; despues de terminar se espera STALE conservando la ultima geometria. No se avanza a otra fase.
