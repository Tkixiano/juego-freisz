# Entrada externa simulada — Godot 4.6.3

El juego inicia en **MOUSE**, conserva el combate y el movimiento existentes. **F2** o el botón «Plataformas» del HUD alternan con **EXTERNAL**. El cambio cancela cualquier arrastre, congela objetivos anteriores y habilita solamente la nueva fuente. Al volver a MOUSE todos los módulos recuperan el control manual. La configuración inicial también está exportada en PlatformManager.

## Simulación

Con el juego ejecutándose y una partida activa:

```powershell
python "C:\godot 4.6\juego frei\juegofrei\tools\simulate_platforms.py"
```

También se puede abrir `tools/StartSimulation.cmd`. Usar F2 para seleccionar EXTERNAL. **Ctrl+C** detiene el envío. `--duration 10` limita la simulación a diez segundos; `--hz`, `--port`, `--host` y `--start-sequence` permiten configurar una prueba. No requiere paquetes Python externos, cámara ni OpenCV. Envía dos plataformas con trayectorias suaves a 30 Hz; la tercera permanece fija y se indica sin seguimiento.

## Protocolo v1

Un datagrama contiene un objeto JSON codificado en UTF-8:

```json
{"version":1,"sequence":100,"modules":[{"id":1,"x":0.35,"y":0.55,"angle":0.0,"visible":true},{"id":2,"x":0.70,"y":0.40,"angle":15.0,"visible":true}]}
```

| Campo | Validación |
|---|---|
| version | Número entero igual a 1; no booleano ni texto. |
| sequence | Entero entre 0 y 9007199254740991, estrictamente creciente. |
| modules | Array, hasta tres módulos, sin IDs repetidos. Puede ser vacío como heartbeat. |
| id | 1 → left, 2 → right, 3 → top. No se crean plataformas. |
| x, y | Números finitos entre 0 y 1. Y aumenta hacia abajo. |
| angle | Número finito en grados entre −180 y 180. Positivo gira en sentido horario. |
| visible | Booleano estricto. false congela inmediatamente la pose física actual. |

Cada módulo debe contener exactamente esos cinco campos. No se aceptan comandos de escala o geometría. Un módulo inválido invalida el datagrama completo; un datagrama rechazado no avanza la secuencia ni renueva el seguimiento. Los módulos omitidos no renuevan su plazo.

Actualización de estabilidad: se admiten los campos opcionales de raíz `sent_unix_ms` y `source_age_ms`, sin cambiar versión ni campos de módulo. Los clientes anteriores siguen funcionando. Permiten rechazar paquetes de más de 350 ms y frames de más de 250 ms, configurables en el receptor. Al drenar por presupuesto se conserva el máximo de secuencia entre ciclos; si ese candidato vence se mantiene la marca de secuencia ya observada, pero no se renueva el seguimiento. No hay latencia extremo a extremo garantizada: ver [la auditoría de estabilidad](../vision/STABILITY_REPORT.md).

En CAMERA v1, el rectángulo normalizado configurable es el área de movimiento de plataformas: origen (150,180), tamaño (980,340). Por ejemplo (0.35,0.55) se convierte a (493,367). No es una calibración de cámara ni representa toda la ventana. PROJECTOR v2 usa otra convención explícita, descrita al final.

## Flujo y seguridad física

- PacketPeerUDP escucha inicialmente en **127.0.0.1:5005**, solamente en EXTERNAL. El receptor acepta remitentes de loopback IPv4. MOUSE cierra el socket.
- El receptor drena la cola sin `wait()` ni hilos bloqueantes desde `_physics_process`, antes de que se muevan las plataformas. Por tick aplica únicamente el paquete válido con mayor secuencia.
- Datagramas limitados a 4096 bytes; buffer UDP de 65536 bytes; presupuesto de 128 paquetes por tick configurable. Si la cola supera el presupuesto, no aplica la parte atrasada y espera a terminar de drenarla. El watchdog sigue funcionando.
- El receptor valida UTF-8 antes de decodificar, para evitar errores de consola con bytes inválidos.
- PlatformManager recibe **objetivos** y comprueba la fuente. DynamicPlatform mantiene el suavizado exponencial (respuesta 8), velocidad lineal máxima 180 px/s, angular 0.70 rad/s y desplazamiento de superficie máximo 4 px/tick. Estos parámetros siguen exportados en cada plataforma. No se duplicó la interpolación ni se tocaron colliders, polígonos o escalas.
- Timeout por módulo: **0.5 s**; timeout de comunicación: **1 s**, configurables en ExternalPlatformReceiver. La falta de datos conserva el último objetivo durante el plazo y luego congela la transformación física alcanzada, sin quitar colisiones ni vidas. La ventana efectiva de seguimiento usa el menor de ambos plazos.
- Una pose válida más reciente recupera el seguimiento con los mismos límites de movimiento. Perder comunicación no reinicia la secuencia: los paquetes viejos siguen rechazados. Cambiar MOUSE → EXTERNAL inicia un flujo nuevo. El simulador comienza con una secuencia basada en el reloj monotónico para poder reiniciarlo sin repetir números anteriores.
- Durante menús y pausa se consumen paquetes, pero no se aplican objetivos. Al reanudar se necesita un paquete nuevo; no se reproduce una cola acumulada durante la pausa.

El HUD muestra modo, estado UDP, paquetes recibidos por segundo (incluidos rechazados), última secuencia válida, módulos detectados, módulos sin seguimiento y **antigüedad desde la recepción local del último paquete válido**. No se mide latencia extremo a extremo: el protocolo no trae reloj de origen sincronizado.

Referencia de la API utilizada: [PacketPeerUDP, documentación oficial de Godot 4.6](https://docs.godotengine.org/en/4.6/classes/class_packetpeerudp.html).

## Alcance

El receptor Godot no depende de OpenCV ni de la webcam; el [detector Python](../vision/README.md) es una fuente independiente. La homografía ahora se calcula y aplica en Python; la validación física del proyector sigue pendiente. No se agregó AR. El receptor no autentica emisores; esta configuración está destinada a procesos locales. UDP puede perder o reordenar datagramas; se prioriza el estado reciente y se congela ante pérdida de seguimiento. Los resultados de las pruebas se registran en `validation/udp_*.json` y en el informe de estabilidad.

## Coordenadas proyectadas (ampliación compatible)

El receptor ahora distingue CAMERA v1 y PROJECTOR v2. La guía vigente es [PROJECTOR_GUIDE.md](../vision/PROJECTOR_GUIDE.md). CAMERA sin campo explícito sigue siendo el protocolo anterior. Los nuevos emisores CAMERA agregan `coordinate_space: "CAMERA"`.

PROJECTOR exige `version: 2`, `coordinate_space: "PROJECTOR"`, `projection_size: [1280,720]` y `orientation_space: "PROJECTOR_PIXELS"`. Conserva los cinco campos de módulo y las reglas de secuencia/frescura. x/y representan todo el lienzo, normalizados por 1279/719. El centro y el ángulo ya vienen transformados por Python. Godot no aplica homografía ni la expansión al rectángulo de CAMERA. Rechaza metadatos incompletos o tamaños incompatibles. Fuera del área permitida de centros, congela el módulo y cuenta `outside_arena`; no cambia geometrías. Un cambio de espacio detiene los objetivos anteriores antes de recibir los nuevos.

Las secciones anteriores describen la etapa CAMERA v1 original.

