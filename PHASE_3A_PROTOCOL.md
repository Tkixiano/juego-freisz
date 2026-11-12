# Protocolo UDP de estructuras dinámicas v1

Es un transporte **independiente** de CAMERA/PROJECTOR. Solo se ejecuta en
`StructureUdpLab.tscn`; Main no lo referencia. No aplica geometrías al backend,
no sustituye plataformas y no incorpora física de materiales ni piso nuevo.

## Configuración y ejecución

Desde la raíz del repositorio:

```powershell
python -m vision.structure_udp_sender --replay juegofrei/validation/replays/07_split.json
```

Abrir `res://scenes/StructureUdpLab.tscn` y ejecutar la escena actual en Godot.
También puede ejecutarse con:

```powershell
& 'C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe' --path juegofrei res://scenes/StructureUdpLab.tscn
```

Loopback IPv4 `127.0.0.1:5015`, distinto del UDP anterior. Cerrar la escena
libera el socket. El emisor se detiene con Ctrl+C, y no exige un receptor activo.
No importa módulos de captura. Los archivos se generan mediante el exportador
existente: `python -m vision.offline_replay`. Se pueden usar todos sus escenarios.

Ejemplo con movimiento, rotación, retirada, agujero o MERGE/SPLIT: elegir el archivo
correspondiente de `juegofrei/validation/replays`. Para reinicios reproducibles:

```powershell
python -m vision.structure_udp_sender --loops 3 --new-session-each-loop
```

Los bucles sin una sesión nueva no rebobinan versiones/épocas: los estados que
contradigan el historial se rechazan. `--hz` 1–120 regula la frecuencia ofrecida,
no garantiza entrega. `--port` permite otro puerto; debe coincidir con Receiver.

## Mensaje lógico

JSON UTF-8, completo en cada actualización. No existen deltas obligatorios.
Conserva los campos de snapshot offline v1 y todos los contratos geométricos v1:

```json
{
  "protocol": "DYNAMIC_STRUCTURES",
  "protocol_version": 1,
  "geometry_contract_version": 1,
  "session_id": "0123456789abcdef0123456789abcdef",
  "session_started_ms": 1790000000000,
  "sequence": 1,
  "logical_time": 0.0,
  "message_type": "SESSION_START",
  "scene_state": "SCENE_EMPTY",
  "empty_confirmed": true,
  "structures": [],
  "identity_epochs": {},
  "events": [],
  "sent_unix_ms": 1790000000000.0
}
```

`SESSION_START` y `SNAPSHOT` contienen el mismo estado completo. El primero
anuncia una sesión y se repite cada 30 mensajes para permitir incorporación
tardía o recuperación de un anuncio perdido. No modifica geometrías por sí solo.

Cada estructura es el diccionario original de Fase 1C: ID string independiente
del color, `geometry_version`, pose global `position`/`orientation_radians`,
`regions` exteriores/agujeros locales, `convex_parts`, `tracking`, `confidence`,
unidades y convenciones. No se normaliza ni aplica homografía en este transporte.
Se conservan `ARENA_PIXELS`, píxeles, radianes y X derecha/Y abajo. Geometría local
y pose permanecen separadas; exteriores tienen área firmada positiva y agujeros
negativa en estas coordenadas. El mapeo sintético identidad no habilita cámara real.

`identity_epochs` asigna una época entera positiva a CADA ID activo. Los eventos
`MERGE`/`SPLIT` llevan listas `parents` y `children`; son informativos. El estado
completo permite recuperar sin haber recibido esos eventos. No se infieren
colisiones ni se conservan padres físicos duplicados: esta fase no crea cuerpos.

## Sesiones y orden

UUID hexadecimal de 32 caracteres. Generación `session_started_ms` entera positiva
hasta 2^53−1; secuencia 1–2^31−1, tiempo lógico finito no negativo y no decreciente
dentro de la sesión. La generación de una sesión distinta debe ser estrictamente
mayor y su primer mensaje aceptado debe ser `SESSION_START`. Una generación igual
con otro UUID se rechaza. El mismo UUID no puede cambiar su generación.

Se valida TODO el snapshot antes de cambiar sesión, secuencia, ledger o último
estado. Un mensaje inválido no consume la secuencia. Duplicados y secuencias
anteriores se rechazan. Saltos se cuentan, pero no impiden recuperación.

Una nueva sesión válida reinicia ledger y secuencia, y descarta reensamblados.
No se mezclan versiones de sesiones diferentes. En la misma sesión no retrocede
la versión geométrica ni cambia el contenido bajo una versión igual. Una época
mayor permite reconocer una reaparición cuya retirada se perdió; nunca se acepta
una época menor. Si el ID fue retirado explícitamente, debe aumentar su época.
El ledger admite 4.096 identidades por sesión, incluso retiradas.

El orden de sesiones usa el reloj local del emisor. Un reloj que retrocede exige
corregir la generación o reiniciar explícitamente el receptor. El watermark no
persiste al cerrar la escena. No hay autenticación: SHA-256 detecta corrupción,
no un emisor local malicioso. No se recomienda exponer el puerto a una LAN.

## Estados del escenario

* `SCENE_ACTIVE`: snapshot válido con al menos una estructura.
* `SCENE_EMPTY`: snapshot completo, lista vacía, épocas vacías y
  `empty_confirmed=true`. La confirmación de ausencia pertenece al productor.
* `SCENE_STALE`: estado LOCAL por timeout de 1.000 ms, también inicial mientras
  no llegó información. No se transmite como observación vacía.
* `SCENE_ERROR`: error explícito del productor; puede incluir su último estado.

Paquetes parciales, duplicados o inválidos no renuevan la frescura. En stale/error
se conserva el último snapshot aceptado. La antigüedad usa reloj monotónico de
recepción y no debe confundirse con latencia de extremo a extremo.

El emisor NO confunde la lista inicialmente vacía del tracker con ausencia:
omite frames de nacimiento pendiente (`PENDING_TOPOLOGY` o candidatos presentes)
y conserva el tiempo lógico del archivo. Solo exporta vacíos confirmados por el
tracker (`TRACKING`, cero componentes) o por una fuente sintética explícita. El
receptor rechaza un EMPTY cuyo diagnóstico contradiga la confirmación. Por eso
el escenario de 3.600 frames fuente emite 3.598 snapshots, omitiendo dos iniciales
sin geometrías confirmadas.

Regla para fases posteriores: habrá piso de seguridad a todo el ancho inferior
en la condición inicial sin estructuras o ante `SCENE_EMPTY` confirmado. No debe
activarse por inaccesibilidad ni por un timeout de estructuras existentes. No se
implementa ese piso en Fase 3A.

## Fragmentación y límites

Cada datagrama es un sobre JSON UTF-8 con:

* `wire="DYNAMIC_STRUCTURES_FRAGMENT"`, `version=1`.
* Sesión, generación y secuencia idénticas al mensaje lógico.
* `index` basado en cero, `count`, `total_bytes`, `sha256` hexadecimal del JSON
  lógico exacto y `data` base64 canónico.

Payload binario por fragmento: **600 bytes**, salvo el último. Máximo datagrama:
**1.200 bytes**. Máximo mensaje: **262.144 bytes**. Guardia de fragmentos: 512;
con ese tamaño de mensaje se utilizan como máximo 437. No se usa compresión.

Máximo 8 mensajes incompletos y 1 MiB de payload reservado agregado. Reserva por
tamaño declarado antes de almacenar; no representa RSS total de Godot (hay
metadatos/objetos adicionales). TTL absoluto de 1 s desde el primer fragmento;
los duplicados no lo prolongan. Se admiten fragmentos invertidos/duplicados
idénticos; conflictos se rechazan. No se publica nada hasta completar longitud,
SHA-256, JSON, identidad del sobre y validación del snapshot. Tras aceptar un
estado nuevo se liberan parciales anteriores de la misma sesión.

Presupuestos del contrato: 32 estructuras/snapshot, 512 partes convexas agregadas,
16.384 vértices de partes agregados, más los límites existentes del validador de
Fase 1C para contornos/agujeros. Pose limitada a ±8.192 px y ±1.000 radianes.

Receiver expone puerto, timeout, memoria y tamaños mediante propiedades exportadas.
En loopback descarta mensajes con `sent_unix_ms` de más de 500 ms o más de 1 s
en el futuro antes de validar geometría. `max_sender_age_ms=0` desactiva ese filtro;
es una configuración local, no cambia el formato. Requiere relojes compatibles.
Lee sin bloqueo en `_physics_process`, hasta 128 datagramas y 2 mensajes completos
por tick, con presupuesto blando de 8.000 µs. Una validación individual puede
superarlo: no se interrumpe un contrato a mitad de su validación. Las métricas lo
registran; no constituye una garantía de tiempo real para la geometría máxima.

## Extensión de materiales (solo datos)

Campo opcional `material_regions` dentro del contrato, con elementos:
`{"material":"GREEN_SOLID", "regions":[...], "convex_parts":[...]}`.
Reutiliza los anillos/partición convexa locales de Fase 1C. No cambia la pose ni
la identidad lógica compuesta. La unión de materiales debe cubrir exactamente la
silueta sin solapamientos ni rellenar agujeros. Cambiar materiales requiere una
nueva versión geométrica. Ausencia del campo significa material aún no anotado;
no se infiere automáticamente del color ni se aplica comportamiento físico.

Reglas definitivas pendientes:

* VERDE / `GREEN_SOLID`: sólido en todas las caras.
* AZUL / `BLUE_BOUNCE`: rebote automático según la normal real de contacto.
* NARANJA / `ORANGE_ONE_WAY`: atraviesa desde abajo/laterales y permite bajar
  estando apoyado mediante abajo.

Una estructura conectada puede tener los tres materiales. La próxima fase debe
resolver normales, fronteras, apoyo, orientación y one-way en superficies
compuestas sin duplicar colisiones ni introducir rellenos.

## Diagnóstico y pruebas

El laboratorio muestra sesión, secuencia, estado, edad local, estructuras,
reensamblados, reserva, rechazos, caducidades y MERGE/SPLIT; refresca a 5 Hz.
`snapshot_accepted` publica un snapshot validado independiente de la copia interna.
`get_status()` expone muestras acotadas de validación/procesamiento/edad del mensaje
y coste por tick; errores acotados a 128 y muestras a 2.048. No imprime cada frame.
También expone la frecuencia real de snapshots aceptados. La caché acotada a los
objetos activos reutiliza solo geometría/materiales con huella idéntica; sesión,
secuencia, versión y metadatos se validan siempre. Los lotes rechazados no cambian
esa caché ni el snapshot anterior.

`sent_unix_ms` permite medir en localhost edad desde creación del mensaje hasta
aceptación (incluye serialización, cola, transporte y validación). Depende del
mismo reloj de Windows; no mide captura, OpenCV ni latencia visual/física.

```powershell
python -m unittest tests.test_structure_udp -v
python -m tests.structure_udp_fixtures
& 'C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe' --headless --path juegofrei --script res://validation/StructureUdpHeadless.gd
python -m tests.run_structure_udp_integration --mode faults --stats artifacts/phase3a/faults_sender.json
python -m tests.run_structure_udp_integration --mode load --objects 8 --parts 16 --hz 30 --seconds 10 --stats artifacts/phase3a/load_sender.json
```

Las dos últimas órdenes requieren el laboratorio abierto. La captura automatizada
de métricas usa `StructureUdpIntegration.gd` desde MCP. No es necesaria para el
funcionamiento normal del emisor/receptor. Resultados medidos en `PHASE_3A_REPORT.md`.
