# Fase 1D — adaptador offline transaccional

Implementación separada del juego principal. Datos generados exclusivamente con arrays sintéticos de NumPy/OpenCV. No se abre `cv2.VideoCapture`, no se utiliza cámara integrada, Redragon ni proyector, y no hay sockets/UDP para las geometrías nuevas.

## Arquitectura

1. `vision/offline_replay.py`: imágenes sintéticas → segmentador y tracker existentes → `ContractExporter` de Fase 1C → archivos de estados completos. Conserva historial de revisión geométrica y épocas de identidad incluso después de retirar un objeto.
2. `OfflineReplayPlayer.gd`: lector acotado de archivos locales, reloj lógico, controles de reproducción, errores de archivo y consultas de estado.
3. `OfflineGeometryAdapter.gd`: secuencias, versiones, identidades, cálculo de diferencias y preparación íntegra del lote. Los eventos de origen son diagnósticos; la fusión/separación se infiere también de las intersecciones entre objetos retirados y nuevos. No depende de recibir todos los eventos históricos para reconstruir un estado completo.
4. `TransactionalGeometryManager.gd`: subclase del administrador anterior, utilizada solo en el laboratorio nuevo. Reutiliza su validador compuesto, cuerpos, protección de personajes y límites de movimiento. Los productores de la API simple quedan bloqueados en esta subclase para evitar escrituras simultáneas; el administrador original conserva su comportamiento.
5. `OfflineReplayLab.tscn`: escena independiente, suelo de seguridad, jugador original, selector de archivo, botones, velocidad y diagnóstico. `Main.tscn` no incorpora ninguno de estos componentes.

## Formato de reproducción v1

Archivo JSON UTF-8 con `replay_version=1`, `geometry_contract_version=1`, `synthetic_only=true`, `tick_hz=30`, `scenario` y `frames`.

Cada frame contiene:

```json
{
  "sequence": 100,
  "logical_time": 3.3,
  "structures": ["contratos completos de Fase 1C, no referencias diferenciales"],
  "identity_epochs": {"s000001": 2},
  "events": [{"type": "SPLIT", "parents": ["s000003"], "children": ["s000001", "s000002"]}]
}
```

El texto entre comillas de `structures` es explicativo; los archivos reales contienen diccionarios completos del contrato v1: ID, regiones exteriores/agujeros, partición convexa local, posición y orientación global, revisión geométrica, seguimiento y confianza. No se creó otra representación de la silueta. Ver `PHASE_1C_REPORT.md` y los JSON exportados.

Tiempo lógico en segundos; pose en píxeles de arena y radianes, ejes X a la derecha/Y hacia abajo. La geometría local mantiene el contrato de Fase 1C. La transformación identidad de cámara sintética a arena está marcada `IDENTITY_SYNTHETIC_LAB_ONLY`; no habilita el uso de coordenadas de cámara física sin calibrar.

Las secuencias son crecientes dentro de cada sesión. La revisión geométrica por ID no retrocede al reaparecer. Si un mismo ID vuelve después de retirarse, aumenta `identity_epochs[id]`. Cambiar la época de un ID todavía activo se rechaza conservadoramente; para saltar una historia que omitió su retirada se debe iniciar una sesión limpia con `request_reset()` y presentar el estado completo. Las revisiones antiguas o una geometría distinta con la misma revisión se rechazan. Un ID desconocido puede comenzar en una época mayor que uno para permitir recuperación desde un snapshot intermedio.

Cada frame es suficiente para reconstruir la geometría sin eventos anteriores. Los saltos de secuencia se admiten, manteniendo las restricciones de versión/época. Después de rechazar un frame, el siguiente snapshot completo puede recuperar el estado; se prueba tanto con un lote inválido como empezando directamente desde un estado posterior a un SPLIT.

## Exportar y abrir

Desde `C:\godot 4.6\juego frei`:

```powershell
python -m vision.offline_replay
```

Genera `juegofrei/validation/replays/manifest.json` y veinte archivos, **4.307 estados** en total. El escenario prolongado tiene **3.600 frames, 120 segundos lógicos, 30 MERGE y 29 SPLIT**. Opciones:

```powershell
python -m vision.offline_replay --output juegofrei/validation/replays --long-frames 3600
```

El escenario de rotación aplica una pose angular sintética conocida al contrato producido por OpenCV, para probar la transformación independiente de la geometría. No es una medición de orientación de cámara.

En Godot abrir `res://scenes/OfflineReplayLab.tscn` y ejecutar la escena actual. Seleccionar archivo y usar **Iniciar**, **Pausar**, **Reiniciar**, **Un fotograma** y **0,25× / 0,5× / 1× / 2×**. A/D y W controlan al jugador reutilizado. No son nuevos controles de combate.

Pausa detiene la lectura y el movimiento hacia objetivos; no pausa al personaje. Una transacción ya preparada y diferida puede terminar al despejarse el conflicto: se trata como el frame ya solicitado, no como lectura de frames nuevos. Reiniciar abre una sesión de reproducción limpia, cancela cualquier lote pendiente y borra secuencias/versiones/épocas; no teletransporta ni reinicia automáticamente al personaje. Retirar todas las colisiones durante un reinicio es una acción explícita, distinta del reemplazo MERGE/SPLIT protegido.

Solo se aplica un frame por tick físico. A 30 Hz de datos y 60 ticks de Godot el máximo es 2×, sin omitir estados intermedios. Valores que excedan esa capacidad se rechazan; no se presenta una velocidad nominal 4× que en realidad avance a 2×. Las demoras físicas detienen el avance del archivo, por lo que el tiempo de pared puede superar al lógico.

## Transacciones y física

El adaptador calcula nuevos, existentes, retirados, cambios de pose/geometría y relaciones de fusión/separación. Primero valida el sobre, IDs/épocas/versiones, TODOS los contratos y el presupuesto de formas. Rechaza también solapamientos entre estructuras lógicas, evitando publicar el compuesto junto con sus padres.

El backend prepara recursos sin tocar cuerpos activos. Reutiliza geometrías y recursos validados cuando el contenido no cambia. Antes del commit comprueba las poses del siguiente paso, penetración de personajes, solapamiento entre estructuras en posiciones intermedias y continuidad del apoyo para cambios de topología. Si hay conflicto, conserva toda la configuración física anterior y registra una sola transición DEFERRED por lote, aunque reintente en varios ticks.

Orden físico: adaptador −80, reproductor −60, administrador −40 y personaje con su prioridad original. El commit no contiene `await`: retira/reemplaza/crea cuerpos y fuerza las transformaciones antes de que corra el jugador. No hay un tick observable con padres y compuesto duplicados, ni un tick sin el apoyo que debería persistir en MERGE/SPLIT. No promete aislamiento frente a scripts externos que inspeccionen el árbol durante señales internas de creación de nodos.

Si un cambio de silueta elevaría el suelo dentro del jugador, queda pendiente. La prueba lo libera con **movimiento real del jugador mediante Input**, no con un teletransporte del adaptador. El backend nunca modifica la posición del personaje. Si la retirada completa es intencional, el personaje puede caer al suelo de seguridad.

Movimientos sin cambio geométrico usan los límites de velocidad y paso superficial. Una nueva geometría se coloca como unidad local+pose, después del preflight, para no mezclar el centro viejo con vértices del centro nuevo. No se reconstruye el cuerpo ni sus formas por una simple actualización de pose.

## Pruebas y resultados

**Pasada gráfica Godot MCP: 134/134. Pasadas headless finales: 127/127.** Las siete filas de diferencia incluyen la carga usada para las seis interacciones gráficas: cuatro botones y los dos selectores. Esas interacciones se probaron en el viewport real mediante mouse/teclado, sin emitir `Button.pressed` ni señales de selección falsas. En este entorno no se enrutan igual los clics de GUI headless, por lo que no se declaran verificados allí.

| Escenario | Estados | Resultado |
|---|---:|---|
| Creación | 12 | Aplicados |
| Movimiento | 68 | Aplicados |
| Rotación | 68 | Aplicados |
| Cambio de silueta | 24 | Aplicados |
| Dos estructuras | 15 | Aplicados |
| MERGE | 30 | 1 fusión |
| SPLIT | 45 | 1 fusión + 1 separación |
| Tres fusionadas | 30 | 1 fusión |
| Agujero | 15 | Conservado |
| Contacto por esquina | 15 | Un ID, varias regiones |
| Eliminación | 30 | Retirada completa |
| Reaparición | 45 | Estado recuperado |
| Duplicado | 16 | 1 rechazo esperado |
| Fuera de orden | 16 | 1 rechazo esperado |
| Geometría inválida | 15 | 1 rechazo esperado, siguiente estado recupera |
| Cambio con personaje | 60 | Prueba física separada difiere y libera el cambio |
| MERGE con personaje | 60 | Mantiene apoyo |
| SPLIT con personaje | 75 | Mantiene apoyo |
| Movimiento simultáneo | 68 | Aplicados |
| Reproducción prolongada | 3.600 | 30 fusiones + 29 separaciones |

Las veinte secuencias se recorren primero con el personaje fuera de su área para aislar validación/reproducción. Después se repiten los tres casos ocupados con el jugador encima, y se mide transporte sobre plataforma móvil.

Medidas de la pasada MCP final:

- **4.591 lotes recibidos, 4.583 aceptados y aplicados, 8 rechazos esperados, 1 lote diferido**. Incluye los escenarios más las pruebas específicas de UI, versiones, recuperación y ocupación; no son solo los 4.307 estados exportados. El diferido pertenece a los aceptados y finalmente se aplica.
- **146 reconstrucciones físicas y 146 preparaciones geométricas**, con reutilización en actualizaciones de pose. Estado final de la prueba: 1 objeto / 1 forma; `get_status()` permite consultar los valores activos durante cualquier escenario.
- **37 MERGE y 32 SPLIT inferidos**, incluyendo repeticiones de pruebas ocupadas. **252 altas/bajas de identidad** contabilizadas como cambios de ciclo de vida; no significan 252 errores de asociación.
- **0 muestras de colisiones duplicadas**, **0 pérdidas de apoyo** durante los MERGE/SPLIT medidos, **0 px² de penetración máxima medida**.
- Transporte horizontal: **126/126 ticks apoyado**, error relativo **0 px**, sin reconstruir geometría. Paso máximo del jugador en los tramos medidos de caída/cambio ocupado: **5,236 px**, por debajo del umbral de salto inesperado de la prueba.
- **0 conflictos de movimiento** en las cargas ejecutadas. El conflicto de penetración de reemplazo se registra como diferimiento preventivo, no como penetración consumada.
- **0 errores/advertencias del runtime en el registro MCP final**. Las tres entradas del registro del reproductor corresponden a pruebas negativas deliberadas: dos velocidades inválidas y un archivo inexistente.

Tiempos medidos en el runtime gráfico, ventana acotada de las últimas **4.096 muestras**; no son FPS:

| Etapa | Media ms | P50 | P95 | P99 | Máximo |
|---|---:|---:|---:|---:|---:|
| Validación/preparación del adaptador | 0,775 | 0,737 | 1,337 | 1,658 | 2,314 |
| Preflight físico del lote | 0,132 | 0,121 | 0,234 | 0,305 | 0,747 |
| Aplicación atómica | 0,116 | 0,083 | 0,166 | 1,396 | 3,008 |

Las muestras y errores están acotados (4.096 tiempos, 128 errores); el archivo de reproducción está limitado a 32 MiB y 10.000 frames, hasta 64 objetos y 2.048 partes por lote, además de los límites por estructura de Fase 1C. El historial de IDs tiene un presupuesto de 4.096. No se ensayó el máximo de carga.

## Correcciones verificadas durante esta fase

- El historial de versiones se vaciaba por compartir una referencia con el diccionario pendiente. Se corrigió la transferencia y se probó su persistencia, versiones positivas antiguas, SPLIT y recuperación de IDs.
- La sincronización visual del selector podía interferir con un menú abierto. Se evita actualizarlo mientras el popup está visible. La prueba de teclado usa navegación soportada por PopupMenu y su ventana real.
- La captura reveló una velocidad visual desactualizada después de cambios por API. Se sincronizó el indicador y se repitieron las **16 comprobaciones de UI** más una comprobación explícita de velocidad real `1.0`/etiqueta `1x`, todas aprobadas. La física y los resultados de la suite completa no cambiaron por esta corrección visual.
- Se eliminó la oferta engañosa de 4× cuando un estado por tick a 30 Hz solo permite 2×.
- Un paso rechazado vuelve a congelar el movimiento si el reproductor está pausado; no deja corriendo el último objetivo por falta de un callback APPLIED.
- Se corrigió una indentación detectada por el primer parsing de Godot. Las ejecuciones iniciales fallidas se conservan como evidencia; no se presentan como resultados aprobados.

## Regresiones y archivos

Python: **51/51**, dos pasadas (incluye 9 pruebas nuevas de exportación y las 42 de Fases 1B/1C). Visión anterior: **59/59** con imágenes sintéticas, cámaras falsas y sockets loopback del protocolo viejo. Fase 1A: **92/92**. Fase 1C: **109/109**. Juego original: **225/225** por Godot MCP, guardado en `validation/full_phase1d.json`; incluye menús, pausa, combate, vidas, reinicio y controles mediante entradas generadas en el viewport. Auditoría headless de carga/parsing: **67 recursos**, sin fallos. La suite offline final se repitió en dos pasadas headless con **127/127** cada una, además de la pasada gráfica **134/134**.

Comparación SHA-256 de **72 archivos preexistentes: ninguno modificado**. Se conserva combate, gravedad, menús, plataformas predefinidas, modos MOUSE/EXTERNAL, Input Map, protocolo UDP anterior y calibraciones.

Creados:

- `vision/offline_replay.py`.
- `tests/test_offline_replay.py`.
- `juegofrei/scripts/geometry/TransactionalGeometryManager.gd`.
- `juegofrei/scripts/geometry/OfflineGeometryAdapter.gd`.
- `juegofrei/scripts/geometry/OfflineReplayPlayer.gd`.
- `juegofrei/scripts/geometry/OfflineReplayLab.gd`.
- `juegofrei/scenes/OfflineReplayLab.tscn`.
- `juegofrei/validation/OfflineReplayValidation.gd` y `OfflineReplayHeadless.gd`.
- Los veinte JSON de `validation/replays/`, su manifiesto, los `.uid` generados y los archivos de evidencia.

Reproducción de las pruebas:

```powershell
python -m unittest tests.test_offline_replay tests.test_structure_merging tests.test_geometry_contract -v
python -m unittest tests.test_vision tests.test_color_isolation tests.test_projection -v
& "C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe" --headless --path juegofrei --fixed-fps 60 --script res://validation/OfflineReplayHeadless.gd
```

`--fixed-fps 60` acelera/controla la simulación; no mide FPS reales. Evidencia: `artifacts/phase1d/`, `validation/offline_headless.json`, `validation/offline_mcp.json`, captura `offline_verified.png`, y el resumen consolidado `artifacts/phase1d/summary.json`.

## Límites y recomendación posterior

- Se comprobó atomicidad observable en los límites físicos, no recuperación ante un cierre del proceso o falta de memoria durante asignaciones.
- StaticBody2D continúa sin barrido continuo. Subidas/rotaciones que invadan al personaje pueden diferirse conservadoramente. No se implementó empuje, aplastamiento ni teletransporte para resolver conflictos.
- Un lote bloqueado detiene la reproducción hasta despejar el conflicto o cancelar/reiniciar. No hay descarte silencioso ni timeout que aplique una geometría insegura.
- La continuidad de apoyo se protege conservadoramente en cambios de topología no vacíos: retirar una plataforma ocupada mientras quedan otras puede diferirse; retirar todo explícitamente permite caer.
- Los cambios de forma y pose son una unidad geométrica: no tienen interpolación continua de siluetas. Los huecos, cuerpos muy detallados y muchos objetos juntos conservan las limitaciones de Fase 1C.
- Los dos minutos lógicos de repetición no equivalen a una prueba de estabilidad de varias horas, ni a hardware físico. No se probaron cámaras/proyección ni se declara rendimiento de captura.

Antes de UDP, conviene conservar este adaptador y definir un transporte versionado de **snapshots completos**, con sesión/épocas, límites de tamaño, fragmentación/reensamblado acotados, checksum, recuperación tras pérdida y política explícita de descarte/supersesión de lotes pendientes. El receptor no debe mutar cuerpos desde callbacks ni aceptar revisiones antiguas. Primero verificar pérdidas/reconexiones sintéticas sobre ese transporte. **Esta fase no implementa nada de ese transporte y se detiene aquí.**
