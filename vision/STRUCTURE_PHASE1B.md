# Fase 1B: siluetas compuestas, fusión y separación

Implementación independiente, exclusivamente con imágenes sintéticas. No abre cámaras, ventanas de captura, dispositivos ni proyección. No modifica UDP, el detector en uso ni Godot. Los módulos nuevos no importan captura, sockets o transporte. Las pruebas nuevas bloquean `cv2.VideoCapture` y `socket.socket` para detectar usos accidentales.

## Ejecutar

Desde `C:\godot 4.6\juego frei`, con las dependencias existentes:

```powershell
python -m unittest tests.test_structure_merging -v
python -m vision.structure_synthetic --benchmark --output artifacts/structure_phase1b
```

La segunda orden genera `report.json` con trazas completas, eventos, resultados por etapa, tiempos y configuración; `scenarios.png` con los doce casos; máscaras individuales y máscara combinada. No inicia el detector normal ni transmite al juego. `--benchmark` es opcional y mide solo procesamiento de arrays sintéticos. No demuestra FPS de cámara o juego.

## Archivos y contrato

- `structure_segmentation.py`: segmentación por HSV, unión binaria, componentes y bordes exactos; configuración `StructureSettings` y diagnósticos `Segmentation`.
- `structure_tracking.py`: identidades independientes del color, confirmación de topología, linaje, caché de geometría y snapshots atómicos.
- `structure_synthetic.py`: fixtures, doce secuencias, informe visual y benchmark reproducible.
- `../tests/test_structure_merging.py`: regresiones automatizadas, con prohibición de hardware/red.

Uso en memoria, todavía sin adaptador para Godot:

```python
from vision.structure_segmentation import StructureSegmenter, StructureSettings
from vision.structure_tracking import StructureTracker

settings = StructureSettings(proximity_pixels=2, merge_frames=3,
                             split_frames=4, near_split_frames=8)
segmenter = StructureSegmenter(color_configs, settings)
tracker = StructureTracker(settings)
segmentation = segmenter.segment(bgr_uint8_array)
snapshot = tracker.update(segmentation)
```

`color_configs` utiliza los rangos `ColorConfig` existentes. Este módulo acepta una lista arbitraria con IDs de color distintos; no cambia la restricción de dos colores del detector anterior. El rojo de las pruebas es únicamente una tercera clase sintética. El filtrado de estructuras usa `StructureSettings.min_area` después de unir las máscaras: no rechaza una pieza porque haya otra comparable del mismo color, ni elimina partes finas conectadas por un filtro de área por color.

Los IDs `s...` identifican estructuras lógicas; los IDs `o...` identifican componentes observados previamente. Ninguno equivale a un ID de color. Si al iniciar ya hay una figura unida, se registra UN componente observado, sin inventar cuántos objetos físicos contiene. `identity_scope` expresa ese alcance. Los colores y su proporción quedan como evidencia diagnóstica, no como identidad única.

Cada estructura exporta posición, anillos locales, área, revisión, estado de antigüedad en frames, miembros conocidos y bloqueos de integración. `rotation_radians=0` es una convención de anillos alineados con los ejes de imagen, NO una estimación de orientación física. Al girar la imagen cambian los vértices. Un compuesto no hereda el ángulo de sus miembros. El JSON del informe es un formato local de evidencia, no un protocolo UDP nuevo.

## Siluetas y contacto

1. HSV independiente por color, incluyendo intervalos H circulares. Se conservan las máscaras individuales sin cierre/dilatación que cree puentes artificiales.
2. Unión OR y componentes conectados con vecindad de 8. Área mínima predeterminada: 64 píxeles. Las coincidencias de dos rangos HSV se contabilizan como conflicto de color, pero la geometría se incorpora una sola vez.
3. Extracción de aristas expuestas de cada celda de píxel y recorrido ordenado. Se eliminan solamente vértices exactamente colineales. Conserva entrantes y agujeros; no usa hull ni bounding box como silueta. Las cajas solo recortan trabajo de CPU.
4. Un píxel `(x,y)` ocupa `[x,x+1] × [y,y+1]`; por eso el área poligonal coincide exactamente con los píxeles aceptados. Coordenadas de salida: `CAMERA_PIXEL_CELL_EDGES`, no normalizadas y todavía sin homografía.

Contacto de lado suficientemente grueso: confirmación de fusión en 3 frames. Contacto solo por esquina: 5 frames. Un cuello que se rompe al erosionar un píxel y deja varios núcleos significativos se marca `AMBIGUOUS_THIN_BRIDGE`: no confirma fusión y mantiene la última salida. Es una decisión conservadora ante ruido, no una prueba del contacto físico real.

`proximity_pixels=2` registra `AMBIGUOUS_PROXIMITY` entre componentes separados. No rellena el espacio ni los fusiona por cercanía. Se mide distancia mínima entre centros de píxeles menos uno: el hueco es exacto en los casos de separación horizontal/vertical; en diagonales es una aproximación de separación rasterizada. Una separación próxima de un compuesto espera 8 frames, frente a 4 frames para separación clara. La clasificación requiere evidencia temporal y no promete distinguir contacto físico de perspectiva/oclusión en una imagen real.

## Identidad, histéresis y geometría

El grafo de asociación usa intersección de máscaras. Para participantes que abandonan su huella al moverse, permite asociaciones cercanas únicas y exige coherencia de área/color al añadirlas a una fusión. La separación recupera miembros solo con correspondencia única de color, área y momentos Hu; posición por sí sola no resuelve identidad. Dos piezas verdes idénticas que se unen y separan reciben IDs nuevos y `IDENTITY_AMBIGUITY`. Evidencia única puede recuperar IDs anteriores, incluso para tres colores.

MERGE sustituye padres por un compuesto; SPLIT sustituye el compuesto por hijos en el mismo snapshot. No se publican ambos simultáneamente. Un cambio de topología pendiente conserva las geometrías anteriores con `stale_frames` creciente. Una pérdida completa se confirma en 5 frames antes de retirar el componente. Reaparición: nueva confirmación, no coordenadas inventadas.

Los contadores de confirmación exigen frames consecutivos y consistencia espacial. Son globales por snapshot: cambios simultáneos esperan el plazo más conservador del conjunto. Un puente ambiguo congela toda la salida para evitar una transición parcial insegura. Esta política puede retrasar componentes independientes y es una limitación deliberada de esta fase.

Traslaciones actualizan pose sin reconstruir vértices. Variaciones de máscara inferiores a 1,5% y distancia máxima de borde de 1,5 píxeles conservan la geometría; los cambios reales la reconstruyen. La comparación se hace contra la geometría aceptada, por lo que pequeños cambios acumulados finalmente la actualizan. Un control final de solapamiento rechaza atómicamente una propuesta que duplicaría área sólida. Los IDs consumidos por una propuesta rechazada no se reciclan. `geometry_rebuilds` cuenta construcciones, incluso propuestas descartadas.

Límites: 64 componentes, 128 miembros conocidos por linaje, 921.600 píxeles. Un exceso de componentes rechaza el frame completo; resolución incompatible requiere tracker nuevo. El historial de eventos no crece dentro del tracker: devuelve solo los eventos del frame; el runner conserva la traza de una prueba finita.

## Integración posterior y límites físicos

**No hay conexión con DynamicGeometryManager ni colisiones nuevas en el juego.** El administrador de Fase 1A admite un polígono simple, hasta 64 vértices. El snapshot identifica candidatos compatibles y declara bloqueos:

- Contacto puntual: una estructura lógica puede necesitar varios anillos exteriores simples. No se crea un puente ficticio ni un único polígono autointersectado.
- Agujeros: se conservan explícitamente; Fase 1A todavía no los representa.
- Contornos rasterizados con más de 64 vértices: se conservan; no se recortan ni convexifican para hacerlos pasar por válidos.
- Anillos que se tocan a sí mismos: señalados, no declarados candidatos para el administrador.

El futuro adaptador deberá transformar TODOS los vértices mediante la homografía, validar/descomponer las geometrías y sustituir lotes de colisiones en un tick físico. No bastará con transformar el centro. Contactos puntuales, agujeros, oclusión por jugadores/manos, desenfoque, sombras y objetos muy delgados necesitan pruebas y decisiones específicas antes de conectar el sistema al combate.

## Evidencia y reproducción

Consultar `../artifacts/structure_phase1b/report.json` para cantidades, eventos y tiempos reales de la ejecución final; `structure_phase1b_tests_final.txt` para el resultado de unittest y `structure_phase1b_compatibility.json` para comparación de archivos preexistentes. Las iteraciones iniciales se guardan en `structure_phase1b_first` y `structure_phase1b_second`.

La primera ejecución detectó pérdida de eventos MERGE cuando un participante se desplazaba fuera de su huella: se corrigió la asociación y se volvieron a ejecutar los doce escenarios. Se añadieron regresiones de confirmación, identidad, máscara, área, ruido, huecos, rotación y movimiento independiente.

Resultado cuantitativo de los escenarios: **12/12**, **253 frames**, **18 MERGE**, **13 SPLIT**. Diez ciclos repetidos producen exactamente diez eventos de cada tipo. Error máximo de área entre máscaras y polígonos: **0 píxeles cuadrados**. Frames con solapamiento entre geometrías emitidas: **0**. La separación de verdes idénticos produce una ambigüedad explícita; los tres colores con evidencia única recuperan sus miembros.

Suite final: **32/32 pruebas**, ejecutada en **dos pasadas completas** después de las últimas correcciones. Registros: `artifacts/structure_phase1b_tests_final.txt` y `artifacts/structure_phase1b_tests_verified_second.txt`. Resumen consolidado: `artifacts/structure_phase1b_summary.json`. Comparación SHA-256 de **63 archivos preexistentes: 0 modificados**. No se declara una partida manual completa ni estabilidad de colisiones de estas siluetas, porque todavía no se incorporaron al juego.

Medición sintética en esta computadora, después de reducir barridos de imagen completa: 35 frames medidos por resolución y 5 de calentamiento. A **640×480: mediana 57,04 ms, p95 66,54 ms**; a **1280×720: mediana 132,87 ms, p95 147,15 ms**. Incluye segmentación, seguimiento y snapshot, sin captura, render, red ni Godot. No alcanza un presupuesto de 33,33 ms para 30 FPS en estas mediciones. Antes de esa optimización localizada se midieron medianas de 77,10 y 197,69 ms, respectivamente; las ejecuciones no constituyen un benchmark de laboratorio controlado. El perfil está guardado en `artifacts/structure_phase1b_benchmark_profile.txt`. Queda pendiente optimizar la representación de máscaras/contornos antes de una integración en tiempo real; no se altera la precisión para ocultar ese costo.

Además se consultó Godot AI MCP: editor real 4.6.3, árbol del laboratorio conservado. El editor conserva una fila antigua de error `const CONVEX`; el archivo actual usa `static var` y la carga headless del laboratorio pasó 92/92. La primera ejecución headless restringida terminó con signal 11 y las pruebas UDP heredadas tuvieron timeout; al repetir fuera de esa restricción, el laboratorio pasó y las 34 pruebas heredadas de color/calibración pasaron. No se interpretan estos fallos de entorno como defectos nuevos ni se ocultan en la evidencia.

No se ha verificado contacto físico real, FPS de cámara, proyector ni colisiones derivadas de estos snapshots. No se ejecutó una partida manual completa en esta fase. Las pruebas de Godot corresponden al laboratorio ya existente y las de UDP al protocolo anterior, con datos sintéticos. No habilitar captura ni transmisión de estas estructuras hasta autorizar la siguiente etapa.
