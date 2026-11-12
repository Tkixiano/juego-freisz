# Informe Fase 3D — UDP multimaterial en la partida

Fecha: 6 de noviembre de 2026. Godot 4.6.3. Datos exclusivamente sintéticos.

## Resultado

Implementada la selección exclusiva OFFLINE/UDP en la partida principal, reutilizando receptor, contratos y backend transaccional existentes. El emisor Python transmite los tres materiales, geometrías compuestas, agujeros, poses, versiones y eventos MERGE/SPLIT. El combate no recibió cambios de reglas, estadísticas ni controles.

La funcionalidad pasa las suites indicadas abajo. **El rendimiento de alta carga sigue siendo una limitación**: validaciones de 32 regiones exceden 16,7 ms y causan descartes por antigüedad. No se certifican 60 FPS sostenidos ni 30 snapshots físicos por segundo bajo esa carga.

## Arquitectura y funcionamiento

Ver [especificación y comandos](PHASE_3D_PROTOCOL.md). `RuntimeGeometrySources` coordina fuentes; `OfflineSourcePort` protege la entrada del replay. UDP conserva reensamblado/integridad, orden y epochs; luego el mismo `OfflineSceneGateway` aplica confirmación y el `MaterialPhysicsAdapter` prepara un lote completo. `MaterialPhysicsManager` hace el commit antes de los jugadores en el ciclo físico.

El callback de recepción solo almacena el estado validado más reciente. No crea cuerpos ni modifica colliders. El puente conserva como máximo un estado y una transacción no aplicada; los eventos necesarios se filtran y las épocas superiores recuperan transiciones omitidas. Se invalidan pendientes y cargas asincrónicas al cambiar de fuente, conservando la geometría comprometida hasta una sustitución segura.

STALE, ERROR y reiniciar sesión conservan la última física válida. Un timeout no activa el piso. EMPTY exige un snapshot completo confirmado; el piso y la retirada diferida reutilizan 3C. Los conflictos con jugadores difieren el lote entero, sin mover automáticamente a los personajes para resolverlos.

## Correcciones realizadas durante las pruebas

1. El timestamp Python se generaba antes de la primera validación/importación: un primer estado grande podía tener más de 2 segundos de antigüedad antes de enviarse. Ahora se genera después de validar; tiene una prueba con reloj simulado.
2. El emisor intentaba recuperar retrasos con ráfagas. Su temporización ahora limita ese catch-up; no transmite aceleradamente fotogramas atrasados después de una pausa de preparación.
3. Al agrupar snapshots válidos, la confirmación del gateway podía quedarse sin observaciones suficientes. Se conservan contadores/tiempo de observaciones validadas, independientes de cuántos estados se apliquen.
4. Se añadieron controles de caducidad tanto antes de preparar como antes de comprometer un estado, evitando aplicar objetivos que envejecieron durante una espera física.
5. Se preservan las épocas de identidad a través de estados completos omitidos y se bloquean escrituras OFFLINE mientras UDP es dueño del backend.
6. El perfil mostró comprobaciones geométricas redundantes. Se añadieron cachés limitadas por entrada exacta y rechazo amplio AABB antes de intersecciones de objetos separados. Los cambios físicos conservan las pruebas de penetración y apoyo. La comparación de rendimiento no es un benchmark A/B controlado: las tasas y tamaños de muestra variaron entre iteraciones.

## Archivos de producción modificados

- `vision/structure_udp.py`, `vision/structure_udp_sender.py`.
- `juegofrei/scripts/structure_udp/StructureProtocol.gd`, `StructureUdpReceiver.gd`.
- `juegofrei/scripts/geometry/MaterialGeometryValidator.gd`, `OfflineGeometryAdapter.gd`, `TransactionalGeometryManager.gd`.
- `juegofrei/scripts/material_physics/MaterialPhysicsAdapter.gd`.
- `juegofrei/scripts/integrated/IntegratedGameManager.gd`, `OfflineSceneGateway.gd`, `SceneSourcePanel.gd`.
- `juegofrei/scenes/IntegratedMatch.tscn`.

Creados: `scripts/integrated/RuntimeGeometrySources.gd`, `OfflineSourcePort.gd`; validaciones `UdpMatchValidation.gd`, `UdpMatchHeadless.gd`, `UdpMatchLiveValidation.gd`, `UdpMatchLiveHeadless.gd`, `Phase3DOriginalRegression.gd`; `tests/material_udp_fixtures.py`, `test_material_udp.py`, `udp_match_live_sender.py`; esta documentación y `PHASE_3D_PROTOCOL.md`. Se generan vectores, reportes JSON, logs y capturas en `validation/` y `artifacts/phase3d/`.

La única adaptación de la suite 3C sustituye su antigua expectativa de ausencia absoluta de un nodo UDP por la condición correcta de inicio OFFLINE y receptor inactivo. No se quitaron pruebas de gameplay.

## Pruebas headless y Python, segunda pasada

| Suite | Resultado |
|---|---:|
| Python: visión sintética, geometría, materiales, replay, protocolos y bootstrap simulado | 158/158 |
| Selección 2B | 92/92 |
| Dash/ataques 2A | 93/93 |
| Polígonos 1A | 92/92 |
| Geometrías compuestas 1C | 110/110 |
| Transacciones/replay 1D | 127/127 |
| Contrato multimaterial | 160/160 |
| Física de materiales 3B.2 | 142/142 |
| Offline multimaterial 3B.3 | 196/196 |
| Partida integrada 3C | 59/59 |
| Transporte 3A | 160/160 |
| Integración nueva 3D por vectores de datagramas | 43/43 |
| Carga/parsing/instanciación | 130 recursos; 0 fallos |

El arranque configurado directamente en UDP pasó además una comprobación independiente. Los vectores 3D recorren selección, ambas fuentes y cambio pendiente, sesiones/epochs, duplicados/desorden/pérdida/fragmentación, recuperación, estados ACTIVE/EMPTY/STALE/ERROR, piso diferido, tres materiales, agujeros/contacto por esquina, silueta/material, MERGE/SPLIT, dash, ataques, daño entre dos jugadores, respawn y reproducción prolongada. Son pruebas automatizadas; no equivalen a una sesión humana.

## Validación gráfica mediante Godot AI MCP

Segunda ejecución del juego histórico: **235/235** comprobaciones generales (menús, controles, física y combate), **111/111** selección/presentación y **37/37** receptor UDP anterior. La primera ejecución se interrumpió por un fallo al abrir el archivo de reporte QA (`FileAccess.open` devolvió null); el relanzamiento completó todas las comprobaciones sin modificar sus criterios. Se conserva ese log inicial. No se considera un fallo de combate corregido ni se oculta el incidente de infraestructura.

La integración nueva también pasó **43/43** dentro de la ejecución gráfica y **15/15** mediante un emisor Python real controlado desde MCP. La secuencia prolongada de vectores contiene **1531 estados completos**. Los logs de las ejecuciones finales no registraron errores de juego.

Se inspeccionaron los árboles de escenas y referencias, se ejecutó la partida desde MCP y se consultaron sus logs. Las pruebas headless se complementan con las pruebas gráficas, no las sustituyen.

## Pruebas UDP real y métricas

Python se ejecuta como un proceso independiente y envía a un PacketPeerUDP real. Las inyecciones con reloj sintético se excluyen de estas mediciones. Los resultados completos están en `artifacts/phase3d/metrics_summary.json` y los archivos `*_final_result.json`.

| Escenario | Aserciones | Estados recibidos / aplicados | Cola máxima |
|---|---:|---:|---:|
| Tres materiales + fallos programados, 15 s | 15/15 | 352 / 209 | 1 |
| 32 regiones cóncavas, 64 partes, 30 Hz solicitados, 12 s | 7/7 | 95 / 11 | 2 |
| Misma geometría, 120 Hz solicitados, 12 s | 7/7 | 12 / 6 | 2 |

Estos 7 controles de carga comprueban recepción, aplicación, estado final, límites y ausencia de penetración profunda; **no comprueban cumplimiento de la frecuencia ofrecida**. Los actores se desactivan en carga para aislar el transporte/backend. Hubo iteraciones anteriores fallidas (hasta 0 estados aplicados); sus logs se conservan, no se cuentan como éxitos finales.

Latencias del escenario normal, milisegundos:

| Medición | P50 | P95 | P99 |
|---|---:|---:|---:|
| Preparación de envío → extracción del último fragmento | 13,76 | 14,85 | 15,90 |
| Validación en receptor | 1,41 | 2,63 | 3,83 |
| Extracción → commit notificado (incluye espera física) | 17,07 | 22,11 | 34,07 |
| Preparación de envío → commit terminado | 30,42 | 35,46 | 46,97 |
| CPU validación backend | 2,41 | 4,42 | 4,97 |
| CPU commit backend | 0,22 | 0,42 | 1,39 |

No son latencias webcam/proyector ni RTT. Se miden con reloj compartido de esta computadora y no generalizan a otra máquina.

En 32 regiones/30 Hz, la validación de receptor tuvo P50/P95/P99 **18,38/23,51/32,66 ms**, y la del backend **28,23/34,95/61,90 ms**. Se descartaron 198 mensajes completos por antigüedad en transporte y otros estados en el puente; las métricas de rechazo por secuencia pueden contar datagramas, no estados. 10 transacciones fueron diferidas por caducidad. A 120 Hz hubo saturación del socket y rechazos por presupuesto de reensamblado. El estado aplicado se acercó al límite de 500 ms. Este es el cuello de botella pendiente, pese a la funcionalidad correcta de recuperación.

## Compatibilidad y pendientes

Las huellas de archivos previos se comparan con `artifacts/phase3d/baseline.json`; las modificaciones de producción están enumeradas arriba. No se cambiaron scripts de movimiento, reglas de combate, selección, gravedad, fuentes HSV, calibración, protocolos CAMERA/PROJECTOR ni geometrías de plataformas originales. Las tres plataformas históricas siguen conservadas y desactivadas en la partida integrada.

Pendiente: prueba humana prolongada con dos jugadores, ensayo de latencia bajo carga representativa y optimización de validación/coalescencia de mensajes grandes. Las propiedades de ONE_WAY y superficies móviles conservan los límites documentados en 3B.2/3C. No se abrió ninguna cámara, no se ejecutó VideoCapture ni se usó proyector. Los tests de bootstrap usan procesos falsos.

No se avanza a otra fase. Se recomienda optimizar el camino de admisión de snapshots grandes antes de sumar captura física o transporte remoto.

## Medición gráfica adicional

En la última prueba con ventana Godot y Python independientes, el monitor integral `TIME_PHYSICS_PROCESS` registró 1063 muestras: P50 **13.49 ms**, P95 **25.34 ms**, P99 **25.34 ms**, máximo **25.34 ms** y **301** muestras superiores a 16,7 ms. Incluye sobrecarga del depurador; no mide render/presentación ni certifica FPS sostenidos. Ver `artifacts/phase3d/live_mcp_metrics.json`.

El monitor de Godot puede actualizar sus valores periódicamente y repetirlos entre consultas; esas 1063 observaciones no constituyen 1063 mediciones independientes de duración de frames. Los histogramas de CPU de validación/commit sí usan el reloj monotónico alrededor de cada operación.

## Partida dejada para inspección

Arrancada la escena principal real desde MCP, con Menta para J1 y Violeta para J2, confirmados mediante F/K. Se probó el selector con eventos de mouse OFFLINE → UDP → OFFLINE → UDP, verificando el modo resultante. Se deja UDP seleccionado y un emisor sintético finito de tres repeticiones de `26_long.json`; después de terminar quedará STALE conservando la última geometría. Puede reiniciarse con el comando documentado. `artifacts/phase3d/integrated_udp.png` contiene la captura final.

La captura final es reciente (`stale_frame: false`); la consulta runtime confirmó dos jugadores, modo UDP, socket abierto, SCENE_ACTIVE, juego sin pausa y capas de las cuatro colisiones históricas en cero. El piso se mantiene por apoyo de un jugador, conforme a su retirada segura. El último log de esa ejecución no contiene errores.
