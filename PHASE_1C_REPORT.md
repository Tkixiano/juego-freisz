# Fase 1C — compatibilidad geométrica y rendimiento

Trabajo exclusivamente sintético. No se abrió ninguna cámara, no se enumeraron dispositivos de captura y no se utilizó proyector. No hay integración UDP de geometrías nuevas ni incorporación al combate. La escena principal sigue siendo `Main.tscn`.

## Resultado geométrico

El contrato local v1 admite un ID lógico con varias regiones exteriores, agujeros interiores y una partición convexa sin solapamientos. Godot representa el conjunto mediante **un StaticBody2D y varias ConvexPolygonShape2D**. Los contactos puntuales conservan regiones separadas: no hay puentes ficticios, convex hulls ni polígonos autointersectados. La representación visual también respeta los huecos.

La partición de la máscara combina recorridos horizontales idénticos en rectángulos convexos verticales. Cada parte está dentro de píxeles sólidos; su unión reproduce la silueta rasterizada, incluyendo concavidades y agujeros. No son cajas que envuelven objetos completos. La alternativa evita incorporar una dependencia de triangulación con agujeros. Una diagonal rasterizada puede requerir muchas partes; no se afirma que sea la partición mínima.

`PolygonValidator.gd` sigue validando la API simple anterior, sin cambios. `CompoundGeometryValidator.gd` valida metadatos, anillos simples, orientación, agujeros interiores, convexidad, contención de cada parte, ausencia de solapamiento y conservación del área. Rechaza partes que rellenan agujeros, cobertura incompleta, degeneración y coordenadas no finitas. Un rechazo conserva la última geometría válida.

Se comprobó el espacio físico real con `intersect_point` en **122.880 centros de píxel por pasada**, correspondientes a diez casos: convexo rasterizado, cóncavo, esquina, arista, tres regiones, agujero, dos agujeros, superficie de un píxel, entrante y agujero rotado/trasladado. Resultado: **0 falsos positivos y 0 falsos negativos**. Error máximo de área por precisión flotante: **0,000159145 px²**. Esto mide fidelidad rasterizada; no demuestra estabilidad universal de colisiones entre contornos arbitrarios en movimiento.

El jugador original se transportó 60 ticks sobre la franja superior de un compuesto con agujero: contacto con el suelo **60/60**, paso máximo **1,5 px**, penetración medida **0 px²**, error de transporte **0,000003815 px**. Las medidas están en `validation/phase1c_geometry_mcp.json`. Además se probaron doce reemplazos de topología bajo un único ID y ausencia de reconstrucción al modificar únicamente pose o metadatos.

## Contrato local v1

Ejemplo completo generado en `juegofrei/validation/phase1c_fixtures.json`. Es un formato local de interoperabilidad y de pruebas; **no es una nueva versión del protocolo UDP**.

| Campo | Semántica |
|---|---|
| `contract_version` | 1 |
| `id` | Identidad lógica, cadena no vacía de hasta 64 caracteres; independiente del color |
| `geometry_version` | Entero 1..2147483647, creciente durante la vida del objeto; no cambia por traslación |
| `coordinate_space`, `units`, `axis` | `ARENA_PIXELS`, `pixels`, `X_RIGHT_Y_DOWN` |
| `position` | `[x,y]` global, sin escala |
| `orientation_radians` | Rotación global en radianes, normalizada al aplicar en Godot |
| `regions` | Lista de `{exterior, holes}`; todos los vértices son locales y ordenados, sin repetir el primero al final |
| `convex_parts` | Partición física local, sin interiores superpuestos |
| `tracking` | `{state: TRACKED/HELD/LOST, age_frames: entero no negativo}` |
| `confidence` | 0..1; evidencia, no probabilidad calibrada de identificación |
| `member_ids` | Miembros observados conocidos, sin inventar identidad física |

En ejes de imagen, los exteriores tienen área firmada positiva (sentido horario visual); los agujeros, negativa. Godot puede normalizar internamente el orden de las partes convexas. Transformación global: `world = position + rotation(angle) * local_vertex`. Una celda de píxel `(x,y)` ocupa `[x,x+1] × [y,y+1]`. El centro geométrico y los vértices locales pueden ser fraccionarios.

El exportador actual genera anillos alineados con los ejes, `orientation_radians=0`: una rotación observada modifica los vértices, sin heredar el ángulo de un componente. La prueba de pose no nula verifica que el contrato y Godot también aplican correctamente una transformación global independiente.

Se conserva el snapshot diagnóstico anterior de Fase 1B por compatibilidad: su campo `manager_candidate` sigue describiendo la API **simple** `create_object`, que no admite agujeros. Para la API compuesta se usa `ContractExporter` y el contrato de este documento; los bloqueos de la API simple no son rechazos de `create_structure`.

La confianza actual es la fracción de píxeles sin conflicto de color, y vale cero si el objeto está retenido. `confidence_kind` declara esa definición. No estima certeza de contacto físico. La histéresis y la ambigüedad de identidad de Fase 1B se conservan.

`source_space=CAMERA_PIXEL_CELL_EDGES`, `mapping=IDENTITY_SYNTHETIC_LAB_ONLY` declaran la conversión identidad usada solo en el laboratorio. No se deben enviar imágenes físicas como coordenadas de arena sin calibrar. En una integración posterior habrá que transformar **todos los vértices** y volver a validar las regiones, sin aplicar dos veces la homografía.

### API de Godot

- `create_structure(contract, color)`: valida y encola un compuesto.
- `assign_structure(contract)`: exige una versión geométrica mayor; valida antes de reemplazar. Si la partición no cambió, no reconstruye formas.
- `update_structure_pose(contract_metadata)`: exige la versión geométrica actual; actualiza pose/estado/confianza sin recorrer anillos ni reconstruir recursos. HELD/LOST detienen el avance hacia un objetivo viejo y conservan la geometría.
- `get_state(id)`: incluye anillos solicitados/comprometidos, versión de contrato, seguimiento, confianza, estado físico y contadores.
- Las APIs simples de Fase 1A, `update_transform`, desactivación y eliminación siguen disponibles. No mezclar fuentes de pose sin un árbitro de control.

Todos los cambios físicos siguen entrando por `_physics_process`. Se conserva la protección ante reemplazos que encerrarían a un jugador, los límites de velocidad y el cálculo del radio usando **todas** las partes. No se reconstruyen formas por mover o girar un objeto.

## Perfilado y optimización

La captura inicial perfilada a 640×480 registró media 53,71 ms: segmentación acumulaba 2,789 s de 3,904 s; extraer bordes consumía 1,329 s en 140 llamadas. El algoritmo recorría una arista por píxel de perímetro incluso en tramos rectos. Esos datos están en `artifacts/phase1c/baseline_profile.txt` y `baseline_profiled.json`; incluyen instrumentación y no se comparan directamente con mediciones sin perfilador.

Cambios basados en esas medidas:

1. Aristas comprimidas en tramos colineales **antes** de recorrer el borde. La única simplificación elimina colinealidad exacta: tolerancia geométrica cero.
2. Caché LRU de siluetas por forma y contenido de la ROI, con comparación exacta adicional a la huella. Límite de entradas: `max_components`. Reutiliza contornos, morfología y clasificación de contacto al trasladar una silueta idéntica.
3. Caché de metadatos de geometría y exportación; invalida por ID, revisión y contenido de los anillos. Las copias devueltas al consumidor son independientes.
4. Traslación de máscaras booleanas sin conversiones repetidas a uint8. No se calculan dos mapas de distancia si la diferencia de área ya obliga a actualizar la geometría.
5. Áreas y traslaciones de las partes vectorizadas. Las pruebas detectaron también un caso de recorte al borde de imagen: ahora reconstruye el contorno recortado en lugar de conservar vértices fuera de la máscara.

No se aplicó simplificación aproximada ni se bajó la resolución. El límite de caché evita retener indefinidamente figuras rotadas distintas. Reutilizar buffers que pertenecen a snapshots anteriores se descartó para evitar mutar observaciones que el tracker aún conserva.

### Comparación pareada final

Tres rondas por versión/carga, 120 imágenes medidas y 10 de calentamiento por ronda: **360 muestras por fila**, 2.160 en total, todas a 640×480. Se alternó el orden antes/después, sin render del juego y sin perfilador. Ambas versiones usan los mismos frames, rangos HSV y el mismo exportador del contrato, para aislar el cambio del pipeline. El código anterior está preservado en `artifacts/phase1c/before/vision`.

| Carga | Versión | Media ms | P50 | P95 | P99 |
|---|---|---:|---:|---:|---:|
| Traslación | Anterior | 22,33 | 21,79 | 28,00 | 31,79 |
| Traslación | Optimizada | **12,31** | 11,74 | 17,24 | 18,80 |
| MERGE/SPLIT | Anterior | 18,55 | 17,57 | 24,74 | 27,32 |
| MERGE/SPLIT | Optimizada | **11,21** | 10,47 | 15,98 | 19,70 |
| Silueta cambia cada frame | Anterior | 32,23 | 31,65 | 41,00 | 47,27 |
| Silueta cambia cada frame | Optimizada | **17,38** | 16,76 | 24,13 | 25,81 |

Se cumple el presupuesto medio inferior a 33 ms en estas tres cargas. Hubo un máximo aislado de **37,90 ms** con cambios de silueta. No se declaran 30 FPS sostenidos de webcam, UDP o juego. El resultado anterior de Fase 1B (57 ms) fue otra carga y otro estado de ejecución; no se usa como comparación controlada. Las primeras pruebas de esta fase con el juego renderizando también fueron más lentas y se conservaron, sin ocultarlas.

Las métricas separan segmentación HSV/unión, morfología, componentes conectados, contornos, simplificación exacta, seguimiento y generación de geometría. `segmentation_other` agrupa asignación de máscaras, caché y proximidad; el total no cuenta dos veces `segmentation_total`. En la tercera ronda con silueta cambiante, las medias fueron: HSV/unión 4,55 ms, morfología 0,04, componentes 2,37, contornos 0,89, simplificación 0,07, otros 1,50, seguimiento 2,50 y geometría 6,01. En una traslación con caché caliente, contornos/morfología/simplificación son cero durante las muestras, porque no se ejecutan.

Los tiempos de geometría corresponden a la partición/exportación en Python; no incluyen el costo de validación/creación física en Godot, captura, serialización de red ni render. Los tiempos del laboratorio Godot incluyen consultas y esperas de validación, no son un benchmark de FPS.

## Pruebas y evidencia

- Python nuevo + Fase 1B: **42/42**, dos pasadas. Incluye comparación de eventos, IDs y máscaras aceptadas contra la versión anterior en los 253 frames de los doce escenarios; sin diferencias.
- MERGE/SPLIT: **12/12 escenarios**, 253 frames, **18 MERGE y 13 SPLIT**, cero geometrías emitidas solapadas.
- Precisión adicional: **270 frames** de traslación/topología/rotación. Cero diferencias entre máscara aceptada y partes exportadas. En frames confirmados de esas cargas, cero diferencias frente a la máscara observada. Los frames retenidos por histéresis se contabilizan aparte en `accuracy.json`.
- Visión anterior: **59/59**, con imágenes sintéticas, cámaras falsas y sockets loopback del protocolo anterior. No se abrieron dispositivos.
- Fase 1A: **92/92**, repetida después de las modificaciones del administrador/cuerpo.
- Contrato compuesto: **109/109** en headless y repetición final por Godot MCP. Incluye consultas físicas, pose global, versiones, conservación tras rechazo, agujeros, personaje transportado y doce reemplazos de topología.
- Juego original: **225/225** mediante Godot MCP. Usa entradas reales de viewport generadas por las pruebas para botones, menús, pausa, combate y movimiento. No equivale a una partida manual con dos personas.
- Headless: **60 recursos** cargados, sin errores; menú, jugadores y plataformas inicializan.
- Comparación de 67 archivos preexistentes: solo cambian cuatro, listados abajo. Combate, gravedad, menús, plataformas predefinidas, Input Map, receptor UDP y calibraciones permanecen intactos.

Evidencia principal: `artifacts/phase1c/performance.json`, `accuracy.json`, `compatibility.json`, `python_first.txt`, `python_second.txt`, `legacy_python.txt`, `mcp_result.json`, `compound_lab.png`; resultados físicos en `juegofrei/validation/phase1c_geometry_headless.json` y `phase1c_geometry_mcp.json`; regresión del juego en `full_phase1c.json`.

## Abrir y reproducir

Abrir `res://scenes/CompoundGeometryLab.tscn` y ejecutar la escena actual. A/D y W reutilizan el jugador original. La escena muestra nueve estructuras sintéticas; el décimo caso rotado se usa solo en validación.

Desde `C:\godot 4.6\juego frei`:

```powershell
python -m unittest tests.test_structure_merging tests.test_geometry_contract -v
python -m unittest tests.test_vision tests.test_color_isolation tests.test_projection -v
python -m vision.structure_synthetic --output artifacts/phase1c/merge_split
python -m vision.structure_benchmark --baseline artifacts/phase1c/before/vision --frames 120 --rounds 3
& "C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe" --headless --path juegofrei --fixed-fps 60 --script res://validation/CompoundGeometryHeadless.gd
& "C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe" --headless --path juegofrei --fixed-fps 60 --script res://validation/PolygonLabHeadless.gd
```

`--fixed-fps 60` controla la simulación; no mide rendimiento real del juego. Las fixtures se regeneran con `tests.test_geometry_contract.write_fixtures(path)`; son datos locales, sin socket.

## Archivos

Modificados: `vision/structure_segmentation.py`, `vision/structure_tracking.py`, `juegofrei/scripts/geometry/DynamicGeometryManager.gd` y `DynamicPolygonObject.gd`.

Creados: `vision/structure_geometry.py`, `vision/structure_benchmark.py`, `tests/test_geometry_contract.py`, `juegofrei/scripts/geometry/CompoundGeometryValidator.gd`, `CompoundGeometryLab.gd`, `juegofrei/scenes/CompoundGeometryLab.tscn`, `juegofrei/validation/CompoundGeometryValidation.gd`, `CompoundGeometryHeadless.gd`, `phase1c_fixtures.json`, este informe y los archivos de evidencia. Godot genera sus correspondientes `.uid`.

## Límites y recomendación para la conexión posterior

- Máximo de 64 regiones, 64 agujeros por región, 2.048 vértices por anillo, 8.192 vértices de anillos por estructura y 512 partes convexas. Piezas muy detalladas pueden superar esos presupuestos; se rechazan conservando la última geometría, no se convexifican.
- Se rechazan anillos autointersectados/autotocantes, agujeros que tocan el exterior y exteriores solapados (incluye una isla anidada bajo el mismo ID). Los contactos puntuales entre exteriores simples sí se admiten. Los casos anidados pueden necesitar una jerarquía adicional; no se rellena el vacío para resolverlos.
- El productor actual representa máscaras rasterizadas. El validador físico admite otras particiones convexas válidas, pero no se verificaron exhaustivamente polígonos continuos arbitrarios ni calibración física.
- La tolerancia numérica de validación es subpíxel; se midió su error en Godot. Consultar centros de píxeles no demuestra exactitud para toda coordenada continua ni ausencia universal de tunneling, aplastamiento o enganches en costuras de muchas formas.
- Los movimientos siguen siendo de StaticBody2D con pasos limitados, sin barrido continuo. La protección frente a encerrar jugadores y las pruebas de transporte no sustituyen un resolvedor de aplastamiento.
- No se probó aún la carga máxima de 64 objetos × 512 formas ni un escenario físico real. Los resultados de CPU no incluyen ese costo físico.

Recomendación: el siguiente paso debe ser **un adaptador offline por lotes**, con presupuesto de partes y tiempo, validación transaccional de toda la sustitución MERGE/SPLIT y prueba de jugadores cerca de cambios de topología. Después de verificarlo se podrá diseñar la transmisión de geometría, con revisiones, límites y caducidad. No basta con transmitir centro/ángulo ni con crear/eliminar cuerpos en cualquier callback. Esta fase no implementa ese adaptador ni cambia UDP. Esperar autorización para continuar.
