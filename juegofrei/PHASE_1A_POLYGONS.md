# Fase 1A: colisiones poligonales dinámicas

Fecha: 05/11/2026. Laboratorio independiente del juego principal, exclusivamente sintético. No se abrió ninguna cámara, no se enumeraron dispositivos de captura y no se ejecutó la salida de proyección. No hay integración nueva con OpenCV ni UDP.

## Arquitectura y reversibilidad

- `scripts/geometry/PolygonValidator.gd`: valida un contorno simple y ordenado; normaliza su sentido y lo descompone con `Geometry2D.decompose_polygon_in_convex`. Verifica convexidad y conservación del área. No usa una caja rectangular como sustituto.
- `scripts/geometry/DynamicPolygonObject.gd`: `StaticBody2D`, una `ConvexPolygonShape2D` por parte válida, representación `Polygon2D` de la silueta e identificación visual. El color no determina identidad. Mantiene revisión y contador de reconstrucción.
- `scripts/geometry/DynamicGeometryManager.gd`: registro de IDs únicos, estado deseado, validación, cola implícita por objeto, creación/reemplazo/desactivación/eliminación y consulta. Todos los cambios del espacio físico se aplican en `_physics_process`, prioridad -40, antes del personaje. Las llamadas desde señales solo modifican estado pendiente.
- `scripts/geometry/PolygonLab.gd` y `scenes/PolygonCollisionLab.tscn`: suelo de seguridad, instancia del `Player.tscn` original, tres objetos sintéticos y secuencia determinista. No usan `PlatformManager` ni las plataformas premodeladas para construir las colisiones nuevas.

El juego principal continúa apuntando a `Main.tscn`; no se añadió el administrador nuevo a esa escena. No se alteraron escenas, scripts, recursos, Input Map o geometrías originales. Se compararon las huellas de 48 archivos de producción preexistentes: ninguno cambió. Retirar los archivos nuevos retira esta fase; no hay autoload ni configuración global nueva.

Los objetos del laboratorio son sólidos en capa 1 y máscara 0. El jugador original ya consulta las capas 1 y 2. No se les asigna comportamiento atravesable: sus paredes, bordes inferiores y huecos forman parte de la silueta sólida. El combate consulta áreas en otra capa y permanece separado.

## Abrir y usar

En Godot, abrir `res://scenes/PolygonCollisionLab.tscn` y ejecutar la escena actual con F6 desde el editor. Otra opción, desde la raíz del proyecto:

```powershell
& "C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe" --path "C:\godot 4.6\juego frei\juegofrei" res://scenes/PolygonCollisionLab.tscn
```

Con el foco en el juego: A/D y W/S reutilizan el movimiento original; F5 inicia la secuencia y F6 restaura el laboratorio. Las teclas F5/F6 de la ventana de juego no deben confundirse con los atajos del editor.

Objetos iniciales: `green_A` (hexágono convexo), `blue_B` (contorno cóncavo en U, tres partes físicas) y `green_C` (triángulo del mismo verde que A). La secuencia desplaza A, lo sube y baja, rota B, cambia C a una U, desactiva C y lo elimina. F6 restaura tres objetos sin duplicados. Los trazos interiores muestran las partes convexas.

## Contrato del administrador

Vértices: `PackedVector2Array`, coordenadas locales en píxeles, orden consecutivo y sin repetir el primer punto al final. Posición: coordenada mundial. Rotación: radianes. Solo se admiten contornos simples, sin agujeros ni anillos múltiples.

```gdscript
geometry.create_object(&"obj_101", points, Vector2(300, 350), 0.0, Color.GREEN)
geometry.assign_polygon(&"obj_101", new_points)
geometry.update_transform(&"obj_101", Vector2(320, 340), 0.15)
geometry.set_collision_enabled(&"obj_101", false)
geometry.remove_object(&"obj_101")
var state: Dictionary = geometry.get_state(&"obj_101")
```

Las operaciones devuelven `bool`: aceptación de una solicitud, no promesa de aplicación inmediata. Los objetos se materializan o actualizan en el tick siguiente. Los IDs se reservan al aceptar creación y se liberan al aplicar eliminación. No se pueden reutilizar antes de ese tick. API de hilo principal; no es una cola entre threads.

Estado: `committed`, `pending_geometry`, `blocked_by_character`, `pending_removal`, objetivos/pose actual, `requested_enabled`/`collision_enabled`, `polygon` solicitado, `committed_polygon`, área, color, cantidad de partes, revisión y reconstrucciones. `object_ids`, `has_object` y `get_body` permiten consultar; este último se usa para inspección/pruebas, no para saltarse el administrador. El último rechazo queda en `last_error`, sin imprimir por frame.

Límites predeterminados: 64 objetos, 64 vértices por contorno, área mínima 32 px², arista mínima superior a 0,01 px, coordenadas locales de magnitud máxima 4096 px y posición mundial máxima 32768 px. Se rechazan valores no finitos, duplicados, autointersecciones, contactos no adyacentes y aristas superpuestas. Un rechazo conserva la última geometría válida, incluso si había una sustitución válida pendiente.

Solo una geometría diferente reconstruye las formas. Traslación, rotación y activación conservan los recursos. Varias órdenes de pose antes del tick se condensan en el último objetivo. Velocidades predeterminadas: 90 px/s, 0,45 rad/s; recorrido máximo de superficie 2 px/tick. No se alteran los parámetros del movimiento del jugador.

Creación, reemplazo o reactivación que encerrarían al personaje se aplazan: `blocked_by_character=true`. Se conserva la colisión anterior o el objeto permanece sin materializar/desactivado. Se reintenta al liberarse el espacio. Se comprueban las formas de los jugadores en su pose lógica y consultas del espacio físico; esto cubre también colocaciones recientes con AABB física todavía anterior. No se expulsan personajes para imponer una silueta nueva. No hay timeout automático de esa espera.

## Correcciones verificadas

1. La primera ejecución detectó tres declaraciones de polígonos que no eran expresiones constantes válidas en GDScript. Se cambiaron a datos estáticos y se volvió a validar mediante MCP.
2. La primera pasada física aprobó 84/86: una subida produjo 59,12 px² de solapamiento (aprox. 1,48 px en la zona plana) y la prueba repetida llegó a 2,53 px². La transformación del `StaticBody2D` se notificaba después de las consultas del personaje. `force_update_transform()` dentro del tick, tras creación/cambio de forma/pose, eliminó el desfase. Se repitieron todos los casos.
3. Al añadir el aplazamiento de reactivación, se reprodujo una colocación reciente del personaje que la consulta de broadphase todavía no veía. Se agregó comprobación directa forma-contra-forma en la pose lógica del jugador antes de la consulta espacial. Creación, reemplazo y reactivación ocupadas quedaron verificadas sin encerrar al personaje.
4. Se corrigió la representación de la descomposición para dibujar sus líneas sobre el relleno, y se ubicaron los IDs debajo de las siluetas para que el jugador no los tape.

## Pruebas ejecutadas

92/92 comprobaciones de API y física aprobadas en el juego gráfico, lanzadas mediante Godot AI MCP. La misma suite aprobó 92/92 en headless con pasos de simulación de 60 Hz. La secuencia F5/F6 aprobó 8/8. Las pruebas usan consultas físicas reales y el controlador original; la carga headless por sí sola no se presenta como prueba funcional.

| Funcionalidad solicitada | Verificación y resultado |
|---|---|
| Convexo | Una forma física poligonal, colisión real: FUNCIONA |
| Cóncavo | Tres partes convexas; el hueco de la U sigue vacío: FUNCIONA |
| Múltiples objetos y mismo color | IDs independientes, misma apariencia y cuerpos distintos: FUNCIONA |
| Posición y rotación | Objetivos alcanzados y recursos conservados: FUNCIONA |
| Cambio de geometría | Revisión incrementada sin reemplazar el cuerpo; inválida posterior no cancela la válida pendiente: FUNCIONA |
| Desactivación y reactivación | Desaparece/reaparece la colisión sin reconstrucción; espera si el personaje ocupa la forma: FUNCIONA |
| Eliminación | Se elimina ID y cuerpo; personaje cae al suelo de seguridad: FUNCIONA |
| Polígonos inválidos | 13 clases de entrada inválida y conservación de la última válida: FUNCIONA |
| Callback de colisión | Solicitudes desde body_entered aplicadas en tick, sin errores de flush: FUNCIONA |
| Suelo irregular | Personaje aterriza en el hueco real y en un lado inclinado del triángulo: FUNCIONA |
| Superficie móvil con personaje | Horizontal, ascenso, descenso y rotación comprobados: CORREGIDO Y VERIFICADO en los escenarios medidos |
| Actualizaciones repetidas | 360 muestras con traslación y giro; formas conservadas, sin recuperaciones de emergencia: CORREGIDO Y VERIFICADO |
| Memoria/nodos | 12 ciclos crear/eliminar no aumentan los nodos vivos: FUNCIONA |

### Métricas de la pasada gráfica corregida

| Escenario | Muestras | Contacto de suelo | Máximo paso del jugador | Máxima área de solapamiento |
|---|---:|---:|---:|---:|
| Horizontal | 100 | 100/100 | 1,50 px | 0 px² |
| Ascenso | 90 | 90/90 | 1,50 px | 0 px² |
| Descenso | 90 | 90/90 | 1,50 px | 0 px² |
| Rotación | 100 | 100/100 | 0,408 px | 0 px² |
| Traslación/giro repetidos | 360 | 360/360 | 0,680 px | 0,001891 px² |

Error de transporte traslacional final: 0 px en horizontal/ascenso/descenso. Recorrido máximo de superficie en el ensayo repetido: 1,5443 px/tick, inferior al límite de 2. Ningún evento de recuperación de atrapamiento en esos escenarios. Se consideraba fallo un salto mayor o igual a 8 px o un solapamiento mayor o igual a 2 px²; se registró el valor real, no solo aprobado/fallido.

El campo genérico `carry_error_px` durante rotación compara traslaciones respecto del origen, no adhesión rígida al cuerpo. El personaje permanece vertical y puede desplazarse sobre una pendiente. No se afirma que quede soldado a una plataforma rotatoria.

No se midieron FPS ni latencia de hardware en esta fase. `--fixed-fps 60` es un paso de simulación para repetir física, no una medición de rendimiento.

## Regresión del proyecto original

- 225/225 comprobaciones de menús, controles, movimiento, gravedad, combate, vidas, victoria, empate y reinicio mediante MCP.
- 37/37 comprobaciones del UDP anterior mediante paquetes sintéticos.
- 12/12 comprobaciones del protocolo PROJECTOR existente con paquetes sintéticos. No se abrió la escena de proyección.
- 34 pruebas Python de reconocimiento por imágenes sintéticas, homografía y sockets locales. No se ejecutaron pruebas que abran captura física.
- Carga/parsing/instanciación/arranque headless del proyecto completo: 55 recursos, sin fallos.
- 48 archivos originales de producción sin cambios según SHA-256; se conserva el mismo `Main.tscn` como escena principal.
- Se inspeccionaron los registros de juego de las ejecuciones corregidas. Los errores iniciales de implementación se conservan como historial, no se borraron para presentar una consola limpia.

Evidencia principal: `validation/polygon_lab_first.json` (primera pasada con fallos), `polygon_lab_verified.json`, `polygon_lab_headless.json`, `polygon_lab_sequence.json`, `external_integration_results.json`, `headless_qa.json`; `../artifacts/polygon_lab.png`, `polygon_lab_headless.log`, `polygon_lab_compatibility_hashes.json`, `polygon_phase1a_python_regression.log` y `polygon_phase1a_headless_load.log`.

## Límites físicos pendientes

- `StaticBody2D` se relocaliza; no realiza barrido continuo como un cuerpo animable. El límite por tick y las velocidades de contacto funcionaron en las pruebas anteriores. No garantizan ausencia de tunneling con siluetas extremadamente delgadas, movimientos arbitrarios o velocidades mayores.
- El aplazamiento de geometría no resuelve toda compresión entre superficies móviles o encerramientos imposibles. No se verificaron todas las combinaciones de objetos cruzados ni una carga de 64 objetos y 64 vértices cada uno.
- No se admiten agujeros interiores ni varios anillos por objeto; se recibe un contorno simple. No hay simplificación de contornos ni reconocimiento/identidad visual en esta fase.
- Las geometrías nuevas se aplican de forma discreta cuando son seguras; no se interpolan sus vértices. Una forma pendiente puede esperar indefinidamente si un personaje no libera la zona.
- El transporte verificado reutiliza el controlador actual de CharacterBody2D y sus velocidades nativas de suelo; no es una solución general para cualquier tipo de cuerpo externo.

## Archivos creados y modificados

Creados: los cuatro scripts de `scripts/geometry/`, `scenes/PolygonCollisionLab.tscn`, `validation/PolygonLabValidation.gd`, `validation/PolygonLabHeadless.gd`, `validation/PolygonLabSequenceValidation.gd` y este documento. Godot generó sus sidecars UID. Se generaron los reportes/captura indicados en `validation/` y `artifacts/`.

Archivos de producción preexistentes modificados: ninguno. Algunas salidas JSON existentes de validación se actualizaron al repetir las regresiones. Utilidad operativa temporal: `../tmp/godot_mcp_client.py`, que llama al servidor Godot AI MCP real por HTTP local cuando el enlace de escritorio expira; no es una dependencia del juego.

## Propuesta de Fase 1B, sin implementar

Mantener primero datos sintéticos: obtener múltiples contornos desde imágenes generadas, asignar IDs persistentes por objeto (independientes del color), simplificar vértices conservando siluetas y convertir todos los puntos al espacio del juego. Diseñar un adaptador o protocolo versionado de ciclo de vida (crear/actualizar/desactivar/eliminar) hacia este administrador, sin romper UDP v1/v2 ni el sistema anterior. Probar dos objetos del mismo color, cruces, oclusiones, entradas/salidas y cambios de contorno. Definir explícitamente política de pérdidas y geometría ocupada.

La Fase 1B no comenzó. La cámara física y el proyector seguirían fuera de alcance hasta autorización y disponibilidad. La sustitución de las plataformas originales tampoco se realizó.

Referencias de API: [descomposición de Geometry2D](https://docs.godotengine.org/en/4.6/classes/class_geometry2d.html), [transformaciones y force_update_transform](https://docs.godotengine.org/en/4.6/classes/class_canvasitem.html), [comportamiento de StaticBody2D](https://docs.godotengine.org/en/4.6/classes/class_staticbody2d.html).
