# Fase 3A — transporte UDP versionado de estructuras

Implementado en un laboratorio independiente. Godot AI MCP confirmó Godot
**4.6.3 stable**, ejecutó la escena, inspeccionó su jerarquía, ejecutó pruebas,
consultó los logs y obtuvo capturas reales. No hay conexión nueva con
DynamicGeometryManager ni con Main. No se usaron cámaras, VideoCapture físico
ni proyector. Los tests anteriores de captura inyectan drivers falsos.

## Arquitectura y archivos

Archivos de producción nuevos:

| Archivo | Responsabilidad |
|---|---|
| `vision/structure_udp.py` | Sobre versionado, sesiones, comprobaciones, fragmentación y reensamblador Python de referencia |
| `vision/structure_udp_sender.py` | Emisor local de los estados completos sintéticos de Fase 1D |
| `juegofrei/scripts/structure_udp/StructureProtocol.gd` | Reensamblado, integridad, orden, sesiones, validación completa, ledger, caché y estados |
| `juegofrei/scripts/structure_udp/StructureUdpReceiver.gd` | Socket PacketPeerUDP no bloqueante, lectura física acotada y señal `snapshot_accepted` |
| `juegofrei/scripts/structure_udp/StructureUdpLab.gd` | Diagnóstico visual a 5 Hz |
| `juegofrei/scenes/StructureUdpLab.tscn` | Laboratorio aislado de cuatro nodos |

Pruebas nuevas: `tests/test_structure_udp.py`, `structure_udp_fixtures.py`,
`run_structure_udp_integration.py`, `run_structure_udp_mcp.py`,
`run_phase3a_regressions.py`; y en `juegofrei/validation`,
`StructureUdpValidation.gd`, `StructureUdpHeadless.gd`,
`StructureUdpIntegration.gd`, `Phase3AOriginalRegression.gd` y
`structure_udp_vectors.json`. Godot genera sus `.uid`.

Documentación nueva: este informe y `PHASE_3A_PROTOCOL.md`. Evidencias y medidas
en `artifacts/phase3a/`; informes de ejecución en `juegofrei/validation/`.

**Ningún archivo de producción anterior fue modificado:** comparación SHA-256
de 76 archivos preexistentes, registrada en `compatibility.json`. Los JSON de
resultados de validación se regeneraron. Se conservaron combate, gravedad,
selección, menús, plataformas, modos MOUSE/EXTERNAL, visión, calibraciones,
contratos geométricos y protocolos CAMERA/PROJECTOR.

Se reutilizan directamente el contrato de Fase 1C, sus anillos y particiones,
`CompoundGeometryValidator.gd`, los veinte escenarios/exportador de Fase 1D y
las suites existentes. No se duplicó el controlador de combate ni el backend
físico. El receptor mantiene datos validados y no instancia cuerpos.

## Protocolo, puerto y ejecución

Especificación completa en [PHASE_3A_PROTOCOL.md](PHASE_3A_PROTOCOL.md).

* Dirección: **127.0.0.1:5015**, independiente del transporte anterior.
* Mensaje lógico: `DYNAMIC_STRUCTURES`, `protocol_version=1`, contrato geométrico
  v1, sesión/generación, secuencia, tiempo lógico, tipo, estado del escenario,
  estructuras completas, épocas, poses, revisiones, seguimiento, confianza y
  eventos MERGE/SPLIT. No usa deltas obligatorios.
* Sobre de fragmento: `DYNAMIC_STRUCTURES_FRAGMENT`, versión 1, sesión/secuencia,
  índice/cantidad, longitud, SHA-256 y base64 canónico.
* Datagramas ≤1.200 B; payload de 600 B; mensaje ≤262.144 B; guardia de 512
  fragmentos (437 efectivos al tamaño máximo). Hasta 8 mensajes pendientes y
  1 MiB de payload reservado; TTL absoluto de 1 s. No es una medición de RSS.
* Hasta 32 estructuras, 512 partes y 16.384 vértices de partes por snapshot,
  además de los límites anteriores de anillos/agujeros.
* Socket no bloqueante en `_physics_process`: hasta 128 datagramas y dos
  snapshots por tick; presupuesto blando configurable de 8 ms. No garantiza
  que un contrato nuevo máximo pueda validarse en ese tiempo.
* Descarta información local de más de 500 ms de antigüedad; no la publica
  después de acumular una cola. Este filtro se puede configurar/desactivar.

Abrir `res://scenes/StructureUdpLab.tscn` y ejecutar la escena actual. Desde la
raíz del proyecto:

```powershell
python -m vision.structure_udp_sender --replay juegofrei/validation/replays/07_split.json
```

Ctrl+C detiene el emisor. Cerrar la escena libera el puerto. No requiere otra
dependencia adicional a las existentes. El emisor también funciona sin receptor,
pero UDP no confirma entrega. Para recrear escenarios o sesiones:

```powershell
python -m vision.offline_replay
python -m vision.structure_udp_sender --loops 3 --new-session-each-loop
```

## Sesiones, recuperación y estados

Una sesión nueva requiere UUID distinto, generación estrictamente mayor y un
`SESSION_START` completo válido. El anuncio se repite cada 30 mensajes para
permitir incorporación tardía. Solo se cambia sesión/ledger/último estado
después de validar todo. Se rechazan duplicados, secuencias anteriores, sesiones
obsoletas, versiones regresivas y épocas inferiores. Una época mayor permite
recuperar una retirada/reaparición omitida por pérdida de paquetes.

Un snapshot posterior recupera el estado sin necesitar todos los eventos
históricos. MERGE/SPLIT se preservan como diagnóstico. No se crean padres y
compuestos físicos, porque esta fase no aplica ninguna colisión.

ACTIVE exige estructuras válidas. EMPTY exige snapshot completo vacío confirmado.
STALE es local por timeout: conserva el último estado, nunca implica vacío.
ERROR es explícito del productor y también debe pasar el contrato. Un paquete
parcial o rechazado no renueva la frescura.

Se detectó un error en la primera versión del emisor nuevo: interpretaba como
vacío los dos frames iniciales de `PENDING_TOPOLOGY`, aunque había candidatos.
Se corrigió usando la evidencia del tracker existente. Esos frames se omiten;
solo se publican geometrías confirmadas o ausencia confirmada. También Godot
rechaza EMPTY si el diagnóstico contradice la ausencia. La regresión específica
pasa. No se cambió el tracker/OpenCV anterior.

## Resultados y regresiones

| Suite | Resultado |
|---|---:|
| Protocolo/contrato final, headless | 160/160, dos pasadas |
| Protocolo/contrato final en Godot MCP | 160/160 |
| Tests Python nuevos de transporte | 21/21 |
| Regresión Python ampliada, última pasada | 128/131; tres timeouts en procesos de captura falsos anteriores |
| Clase completa de captura falsa, repetida aisladamente | 5/5 |
| Regresión gráfica general original | 235/235 |
| Selección, personajes y fallbacks gráfica | 111/111 |
| Selección/combate headless | 92/92 |
| Dash/ataques Fase 2A | 93/93 |
| Polígonos Fase 1A | 92/92 |
| Geometrías compuestas Fase 1C | 109/109 |
| Adaptador/reproducción Fase 1D | 127/127 |
| UDP anterior en juego real | 37/37 |

Los 44 vectores de protocolo incluyen las 22 situaciones solicitadas y casos
adicionales: geometría inválida, caché sin omitir validación de metadatos,
materiales mezclados/solapados/desconocidos, UTF-8/base64 inválidos, límites de
memoria, sesión nueva inválida sin desplazar la vigente, épocas de recuperación,
agujeros, esquinas y rotación. Los estados publicados son copias independientes;
mutarlos no cambia el almacenamiento interno.

El test UDP real de fallos comprueba inicio, nueva sesión, sesión vieja,
duplicados, fragmentos invertidos, pérdida/incompletos, caducidad, recuperación,
MERGE/SPLIT y los cuatro estados. La pasada final aprobó **49/49 comprobaciones**:
49 snapshots aceptados y siete rechazos esperados (tres fragmentos obsoletos,
tres duplicados y un snapshot con revisión reutilizada para contenido distinto).
Hubo un incompleto caducado, dos sesiones, una fusión y una separación. La primera
pasada aceptaba 51 mensajes; la corrección de los dos nacimientos pendientes
explica la reducción a 49. Los rechazos de vectores corruptos
son resultados esperados, no errores de ejecución de Godot.

Las suites gráficas se ejecutaron con entradas automatizadas y el viewport real;
no se afirma una partida manual de dos personas. Los tests sintéticos de captura
no prueban hardware.

### Incidencias del entorno y del arnés

La primera regresión Python dentro del aislamiento tuvo sockets/procesos falsos
bloqueados. Fuera de ese aislamiento pasó 129/129 antes de agregar dos tests
nuevos de ausencia. La pasada ampliada posterior tuvo timeouts en cinco tests
preexistentes de procesos de captura falsos ejecutados junto con otras suites;
sus resultados finales aislados se registran por separado. No se cambiaron sus
umbrales ni se modificó OpenCV para ocultarlos. La clase repetida aisladamente
pasó **5/5** (`fake_capture_isolated.txt`). Una nueva pasada completa sin otras
suites simultáneas pasó **128/131**: volvieron a fallar por timeout
`test_hung_open_has_bounded_close`, `test_hung_read_restarts_and_closes` y
`test_open_read_disconnect_and_release_with_fake_device`. La causa exacta de la
intermitencia no quedó aislada; no se atribuye como hecho al paralelismo ni al
transporte nuevo. **No hay una pasada final 131/131 limpia.** El resto de las
pruebas y los 21 tests nuevos pasaron; no se abrió ningún dispositivo real.

Una ejecución headless inicial sufrió signal 11 antes del banner; las repeticiones
finales completaron sin ese fallo. La ejecución larga síncrona de MCP excedió su
límite de 10 s aunque terminó las pruebas; el runner final cede frames y se
consulta de forma asíncrona. Se corrigieron dos fallos del arnés (comparar razón
ausente como Dictionary/String y esperar el archivo desde antes de armar el
timer MCP). Los tests finales verificaron esos cambios.

Datos UTF-8 corruptos inicialmente producían mensajes del decodificador Godot;
ahora se validan antes de decodificar y se rechazan silenciosamente con contador.
Los logs anteriores se conservan y no se presentan como ejecuciones limpias.
La consulta de editor conserva además errores históricos de Phase2BValidation y
PolygonLab. Se comprobó mediante MCP que ambos scripts cargan actualmente y
`can_instantiate()` devuelve true. La advertencia nueva de variable local
confundible en el arnés UDP se corrigió renombrándola; se repitieron las 160
comprobaciones headless y MCP con éxito. La consulta final del **juego** no
registró errores ni advertencias de ejecución; el historial del editor no se borró.

## Perfilado y límites medidos

Ensayos locales en esta computadora; no son una garantía de FPS ni una medida
de captura/detección/render/física. Edad del mensaje = reloj de Windows al crear
el JSON hasta aceptación en Godot: incluye serialización, cola, transporte y
validación. La antigüedad de recepción usa otro reloj monotónico y se informa
separadamente.

| Carga (10 s a 30 Hz ofrecidos) | Aceptados | Edad media | P50 | P95 | P99 |
|---|---:|---:|---:|---:|---:|
| Inicial, 8 estructuras/128 partes, presupuesto 3 ms | 86/300 en ventana de 14 s | 5.116 ms | 5.103 ms | 9.556 ms | 9.928 ms |
| Final, 2 estructuras/2 partes | 300/300 | 12,82 ms | 13,23 ms | 20,16 ms | 22,87 ms |
| Final, 8 estructuras/128 partes | 300/300 | 91,06 ms | 58,43 ms | 234,77 ms | 264,20 ms |
| Repetición, 8 estructuras/128 partes | 300/300 | 126,18 ms | 107,53 ms | 255,65 ms | 258,23 ms |

En la medición inicial quedaban mensajes en cola; 86/300 no significa pérdida
definitiva de todos los restantes. No se afirma que esa versión funcionara bien.

La geometría repetida causaba aproximadamente 46 ms de validación por snapshot.
Se reutilizó el criterio de caché del backend offline: huella de silueta y
materiales, validación completa cuando cambia, metadatos/versiones siempre
revisados y commit del caché solo con el lote válido. Se optimizaron verificaciones
textuales con operaciones nativas y se ajustó el presupuesto tras medir.

Validación final (media/P50/P95/P99):

* Carga liviana: **0,953 / 0,913 / 1,178 / 1,558 ms**.
* Carga exigente repetida: **7,679 / 7,493 / 10,160 / 11,917 ms**.
* En esa carga se validaron ocho geometrías y se reutilizaron 2.392, sin
  reconstrucciones físicas (no hay cuerpos conectados).
* Frecuencia aceptada: 29,95 Hz liviana y 29,96 Hz exigente en esos ensayos.
  La repetición liviana recibió 300/300 a 30,00 Hz.
* P99 del tick del receptor: 5,85 ms liviana y 24,51 ms exigente repetida.
  **La carga exigente supera el presupuesto de un frame de 60 FPS.**

### Reproducción UDP prolongada real

Se reprodujo `20_long.json` durante **120,0005 s de reloj de pared**, con el
emisor Python y PacketPeerUDP de Godot ejecutándose realmente en localhost:

* 3.600 frames fuente; **3.598/3.598 snapshots confirmados aceptados**.
  Se omitieron correctamente dos frames iniciales de nacimiento pendiente.
* **8.997/8.997 datagramas**, cero errores de envío, cero rechazos, cero huecos
  de secuencia; una sesión, **30 MERGE y 29 SPLIT**.
* **1.811/1.811 comprobaciones** de integración, incluidas orden, límites y
  cantidades finales. Frecuencia aceptada: **30,0015 Hz** sobre la ventana de
  muestras retenidas, no una promesa de FPS del juego.
* Edad del mensaje: media **11,582 ms**, P50 **11,370 ms**, P95 **17,304 ms**,
  P99 **20,935 ms**; últimas 2.048 actualizaciones de 3.598.
* Validación: media **0,884 ms**, P50 **0,847 ms**, P95 **1,434 ms**, P99
  **1,938 ms**; últimas 2.048 muestras. Tick del receptor P99 **6,108 ms**
  sobre su ventana retenida.
* Reserva máxima de payload incompleto **1.742 B** en este escenario liviano;
  no mide la memoria total del proceso ni la carga máxima admitida.

La repetición liviana recibió 300/300: edad media 13,044 ms, P50 13,307 ms,
P95 14,874 ms y P99 16,191 ms. Las muestras/estadísticas de cada ensayo quedan
separadas; no se promedian percentiles entre ejecuciones.

Procesamiento por datagrama, ventana acotada: P50/P95/P99 liviano
0,753/2,547/2,959 ms (900 muestras); exigente repetido
0,524/8,847/13,045 ms (últimas 2.048 de 5.400 muestras). El datagrama final incluye
la validación del mensaje, por eso tiene un coste distinto al de un parcial.

La carga exigente no demuestra que la geometría máxima pueda mantenerse a 30 Hz
ni que el juego integrado conserve 60 FPS. Es necesario separar/progresar la
validación pesada y medir el coste físico antes de conectar al combate.

## Materiales y siguiente integración

Quedan documentados y validados como **datos**, sin comportamiento físico:
VERDE sólido en todas sus caras; AZUL rebote automático según normal de contacto;
NARANJA one-way atravesable desde abajo/laterales y descenso con abajo estando
apoyado. `material_regions` reutiliza el contrato local de anillos/partición
convexa, admite materiales diferentes bajo un ID compuesto y exige cobertura
exacta sin solapamientos ni relleno de agujeros.

El piso futuro ocupará el ancho inferior solo ante condición inicial sin
estructuras o EMPTY confirmado. La inaccesibilidad o STALE no deben activarlo.
No se implementó piso ni se alteraron las plataformas existentes.

Antes de Fase 3B.1 se recomienda:

1. Entregar el snapshot aceptado al adaptador transaccional en frontera física;
   distinguir **recibido/validado** de **aplicado/diferido por física**.
2. Conciliar sesiones nuevas sin vaciar arbitrariamente el soporte de jugadores.
   El adaptador offline actual es más estricto ante un salto de época de un ID
   todavía activo; habrá que tratar explícitamente la reaparición omitida antes
   de conectar, sin confundirla con continuidad de identidad.
3. Mantener commit completo, versiones/huellas que incluyan materiales y la
   prevención existente de penetración. No teletransportar personajes.
4. Probar normales, contactos entre materiales, rebote y one-way inclinado en una
   fase física separada; no inferir material por ID/color ni crear colisiones
   duplicadas de padres y compuestos.
5. Reducir coste de validaciones frías y medir casos de máximo tamaño. El
   protocolo es local y sin autenticación/retransmisión/ACK; SHA-256 no autentica.
   El orden de sesiones depende de generación monotónica y el watermark no se
   conserva al reiniciar el receptor.

**No se avanzó a Fase 3B.1.**
