# Fase 3D — Transporte multimaterial integrado

## Alcance y compatibilidad

La partida `res://scenes/IntegratedMatch.tscn` reutiliza el backend multimaterial transaccional. La fuente predeterminada es **OFFLINE**. `UDP` utiliza el receptor existente, sin acceso a cámaras ni proyector. CAMERA/PROJECTOR continúan siendo protocolos independientes. No hay un segundo sistema de colisiones.

Flujo: `PacketPeerUDP → reensamblado/integridad → StructureProtocol → RuntimeGeometrySources → OfflineSceneGateway → MaterialPhysicsAdapter → MaterialPhysicsManager`. OFFLINE entra por `OfflineSourcePort` al mismo gateway.

## Versión

El sobre fragmentado sigue siendo `DYNAMIC_STRUCTURES_FRAGMENT`, versión **1**. El mensaje lógico se identifica como `DYNAMIC_STRUCTURES`, `protocol_version: 2`, `geometry_contract_version: 1`, `material_contract_version: 1`. Es una extensión explícita del mensaje lógico 3A; las reproducciones offline no cambian de formato.

Se conservan `session_id`, `session_started_ms`, `sequence`, `logical_time`, `message_type` (SESSION_START/SNAPSHOT), `scene_state`, `structures`, `identity_epochs`, `events`, `empty_confirmed`, `sent_unix_ms`. V2 exige `region_identity_epochs` con exactamente las regiones presentes y épocas enteras positivas. Cada estructura conserva su contrato geométrico/multimaterial v1, pose global, regiones locales, agujeros, descomposición convexa, versiones, confianza y seguimiento.

Los materiales admitidos conservan sus nombres existentes: `GREEN_SOLID`, `BLUE_BOUNCE`, `ORANGE_ONE_WAY`. No se deducen de un ID ni se cambian dimensiones a partir del material. El receptor aislado mantiene compatibilidad con mensajes lógicos v1; la partida multimaterial exige v2. Cambiar de versión dentro de una misma sesión se rechaza.

## Transporte y límites

- Loopback `127.0.0.1:5015`, independiente del receptor antiguo 5005. Configurable en `UdpTransport`.
- Datagrama máximo 1200 bytes; fragmento de carga 600 bytes; mensaje máximo 262144 bytes; máximo 512 fragmentos; SHA-256.
- Reensamblado: 8 mensajes, 1 MiB, caducidad 1000 ms. Socket: 2 MiB. Presupuesto por tick: 128 datagramas, 2 mensajes completos y 8000 µs. Una validación individual puede superar ese presupuesto; no es un límite preventivo de CPU.
- Contrato: hasta 32 estructuras; límites de partes/vértices y 4096 identidades acumuladas por sesión. Las regiones tienen validación propia.
- STALE tras 1000 ms. Antigüedad máxima de admisión configurada: 500 ms; se vuelve a comprobar antes del commit físico. La duración de ese commit se suma después.
- Puente: un estado completo más reciente y una transacción pendiente, como máximo. Métricas acotadas a 2048 muestras por serie; backend a 4096.

## Orden, recuperación y cambio de fuente

Una sesión nueva necesita SESSION_START y una generación posterior; no borra el escenario físico. Sesiones antiguas, secuencias duplicadas/antiguas, versiones geométricas regresivas y épocas reutilizadas se rechazan. El emisor vuelve a anunciar periódicamente su sesión para recuperarse de una pérdida inicial.

El puente puede sustituir una transacción **aún no aplicada** por un estado completo más reciente ya validado. Conserva y filtra eventos de topología; los epochs superiores permiten recuperar una retirada/reaparición omitida. Los eventos son diagnóstico; la física se obtiene siempre del estado completo. No se ejecutan diferenciales incompletos.

Al alternar OFFLINE/UDP se pausa el replay, se invalidan cargas asincrónicas y pendientes, se cierra/vacía el socket y se limpia la transacción no aplicada. Los colliders comprometidos permanecen hasta otra transición segura. El watermark de transporte conserva la protección contra sesiones/paquetes viejos al volver a UDP.

ACTIVE/EMPTY necesitan al menos 3 observaciones y 0,10 s. Las observaciones UDP válidas cuentan aunque sus snapshots se agrupen; una sola detección no confirma un cambio. STALE y ERROR congelan el último estado válido y nunca implican EMPTY. El piso usa la lógica de 3C: solo inicio sin estructuras o EMPTY confirmado; retirada diferida si un jugador depende de él.

Los campos `_rx_*`, `_validated_usec`, `_observed_*`, `_apply_deadline_usec` y `allow_identity_recovery` son metadatos **locales**, no campos confiables del emisor. El puente los genera/sobrescribe y el puerto OFFLINE elimina los indicadores especiales.

## Uso

Desde `C:\godot 4.6\juego frei`:

```powershell
python -m vision.structure_udp_sender --replay juegofrei/validation/material_replays/26_long.json --hz 30 --loops 3 --new-session-each-loop --stats artifacts/phase3d/demo_sender.json
```

Abrir la escena principal, elegir personajes y confirmar LISTO ambos. En el panel de fuente elegir **UDP :5015**. Para regresar, seleccionar **OFFLINE** y elegir un replay o `ESCENARIO VACÍO CONFIRMADO`; los botones del replay se deshabilitan durante UDP. También se puede configurar `Sources.startup_mode` en el inspector.

El emisor funciona sin Godot; Godot puede iniciar sin emisor. Ctrl+C detiene el emisor. Tras finalizar se espera STALE, conservando la geometría. Para confirmar EMPTY usar un replay con estados vacíos (por ejemplo `17_removal.json`), no apagar el proceso.

Los fixtures de laboratorio conservan el desplazamiento de arena existente `(300,180)` en el gateway. No hay homografía en este transporte ni transformación de cámara; un emisor futuro deberá respetar esta configuración de coordenadas.

## Métricas

`receiver_age_ms`: sello de preparación de envío → extracción del último fragmento por Godot; incluye serialización, cola de socket y tiempo local, no captura ni latencia cámara/pantalla. Requiere reloj local compartido.

`validation_ms`: procesamiento del último fragmento y validación del contrato. `application_ms`: extracción → notificación APPLIED, incluye espera/histéresis/validación/límite físico. `applied_sender_age_ms`: preparación del envío → commit terminado. Los percentiles de estados aplicados no incluyen los descartados: se deben leer junto a sus contadores.

`TIME_PHYSICS_PROCESS` se captura adicionalmente en la prueba nativa final; los tiempos de scripts individuales no equivalen al tiempo total de física o render. Las pruebas de inyección con reloj sintético no son mediciones de latencia real.

## Riesgos observados

La carga de 32 regiones/64 partes excede el presupuesto de un frame en varias validaciones. Incluso a 30 Hz existen descartes por edad; a 120 Hz solicitados puede saturarse el buffer UDP. Las protecciones mantienen las colas acotadas, pero no garantizan recepción a esa tasa ni 60 FPS. El siguiente trabajo recomendado es perfilar/coalescer antes de la validación geométrica costosa, con pruebas de sesiones/epochs, y reducir validaciones redundantes de snapshots móviles sin perder precisión.
