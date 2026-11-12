# Fase 3B.2 — Física de materiales en laboratorio

Proyecto: `juegofrei`. Motor ejecutado: Godot 4.6.3 stable oficial. Trabajo exclusivamente sintético; no se abrió ninguna cámara ni se utilizó proyector. No se conectó OpenCV ni UDP al laboratorio.

## Arquitectura implementada

`MaterialPhysicsLab.tscn` es independiente de `Main.tscn`. Usa dos instancias del **Player.tscn existente**, su controlador de movimiento y combate, sus hitboxes y el mismo método de resolución de impactos de GameManager. El laboratorio no duplica el controlador ni el algoritmo de combate. Su único servicio GameManager, sin interfaz ni procesamiento propio, se libera al cerrar la escena.

El flujo es:

1. Fixtures locales producen estados completos del contrato geométrico v1 con extensión multimaterial v1 existente.
2. `MaterialPhysicsAdapter` valida la estructura lógica, épocas, versiones y regiones; conserva el ID lógico y deriva cuerpos físicos por ID de región.
3. `MaterialPhysicsManager` extiende el backend transaccional existente: prepara todo el lote, verifica ocupación y continuidad del apoyo y lo aplica antes de que se procesen los jugadores.
4. `MaterialPolygonBody` representa cada región mediante StaticBody2D. Las regiones de una estructura comparten pose e identidad lógica, pero conservan material y colisiones independientes.
5. `MaterialContactAdapter`, instalado solamente en los jugadores del laboratorio, responde a contactos reales de `move_and_slide`. Player sigue realizando su movimiento normal una sola vez por tick.

Se añadieron puntos de extensión con comportamiento predeterminado equivalente al backend anterior. La comparación SHA-256 de los **91 archivos de producción previos** detectó solamente dos archivos existentes modificados: PlayerController y TransactionalGeometryManager. No faltan archivos. OpenCV, protocolos, menús, gravedad, recursos de movimiento, escenas originales y plataformas predefinidas conservaron sus hashes iniciales de esta fase. El repositorio ya contenía cambios de fases anteriores; no fueron revertidos.

### SOLID

Reutiliza la descomposición convexa del contrato compuesto. No rellena agujeros ni reemplaza concavidades por rectángulos. Las formas se reconstruyen al cambiar la geometría o material, no al cambiar solamente la pose.

### BOUNCE

Usa la **normal física de KinematicCollision2D**, no la dirección entre centros. La velocidad resultante combina impulso normal y una fracción configurable de la velocidad tangencial entrante. Impulso y velocidad total tienen límites; el límite total prevalece incluso sobre un mínimo de impulso incompatible.

Un latch por cuerpo evita repetir el rebote durante un contacto continuo. Se rearma después de separarse físicamente, con margen de seguridad. Sólo se aplica un lanzamiento por tick, evitando acumulaciones en contactos múltiples. No aplica daño. El contacto interrumpe el desplazamiento del dash y conserva su invulnerabilidad restante. El hitstun y el porcentaje no se borran. Durante hitstop se conserva la pausa del combate; la respuesta ambiental se evalúa al reanudarlo.

### ONE_WAY

No activa one-way sobre cada pieza convexa de un volumen. Extrae segmentos de los contornos reales, incluidos los bordes de agujeros. Sólo habilita caras cuya normal mundial apunta suficientemente hacia arriba. Las superficies verticales e inferiores no bloquean. Los tramos enterrados en otras regiones de la misma estructura se recortan; no se agregan volúmenes sólidos ni caras internas atravesables ficticias.

Los segmentos usan la colisión unidireccional nativa de Godot. La rotación cambia qué caras quedan habilitadas sin reconstruir las formas.

Abajo agrega excepciones **por cuerpo de apoyo naranja**, sin teletransportar ni cambiar globalmente la máscara. La excepción se elimina cuando el rectángulo del jugador, ampliado con un margen, ha salido de la región. Se deshabilita el snap durante el descenso. Un apoyo sólido en una unión impide el descenso. Defensa o ataque recién aceptados tienen prioridad sobre el descenso. El descenso no se activa desde SOLID.

## Seguridad transaccional

- Geometría/material inválidos rechazan el lote completo; se conserva el último estado válido.
- El commit actualiza la representación lógica antes de emitir la señal pública APPLIED: el observador de pruebas comprobó coherencia entre mapas lógicos y cuerpos físicos.
- La creación/reconstrucción que penetraría al personaje se difiere, sin moverlo automáticamente.
- La traslación acotada de un apoyo predice el transporte nativo del jugador. Se verifica el siguiente paso físico, no se mueve al jugador desde el gestor.
- Si el transporte lo empujaría contra un sólido externo en la capa 1, el movimiento de las regiones se detiene y registra el conflicto. También se conservan las verificaciones previas contra otras regiones administradas.
- Una petición puede estar aceptada mientras su objetivo de pose aún no se alcanzó; los conflictos posteriores de movimiento quedan registrados separadamente de los lotes diferidos.
- La pendiente o una rotación ocupada incompatible puede quedar detenida hasta que el personaje abandone la zona. No se fuerza el avance mediante teletransporte.

## Archivos

Existentes modificados:

- `juegofrei/scripts/PlayerController.gd`: hooks opcionales de entorno; sin adaptador continúa el flujo normal.
- `juegofrei/scripts/geometry/TransactionalGeometryManager.gd`: hooks de fábrica, material, preflight y soporte; conserva comportamiento por defecto.

Creados:

- `juegofrei/scenes/MaterialPhysicsLab.tscn`.
- `juegofrei/scripts/material_physics/MaterialPhysicsLab.gd`.
- `juegofrei/scripts/material_physics/MaterialPhysicsFixtures.gd`.
- `juegofrei/scripts/material_physics/MaterialPhysicsAdapter.gd`.
- `juegofrei/scripts/material_physics/MaterialPhysicsManager.gd`.
- `juegofrei/scripts/material_physics/MaterialPolygonBody.gd`.
- `juegofrei/scripts/material_physics/MaterialContactAdapter.gd`.
- `juegofrei/validation/MaterialPhysicsValidation.gd`.
- `juegofrei/validation/MaterialPhysicsTestInput.gd`.
- `juegofrei/validation/MaterialPhysicsHeadless.gd`.
- `juegofrei/validation/MaterialLabControlValidation.gd`.
- `juegofrei/validation/Phase3B2OriginalRegression.gd`.
- Este informe y resultados/capturas en `artifacts/phase3b2/`.

Las suites también regeneraron sus JSON y capturas de validación habituales; esos archivos son resultados, no cambios al juego.

## Abrir y controlar el laboratorio

Abrir `res://scenes/MaterialPhysicsLab.tscn` y ejecutar la escena actual (F6). También:

```powershell
& 'C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe' --path 'C:\godot 4.6\juego frei\juegofrei' res://scenes/MaterialPhysicsLab.tscn
```

Se deja abierto mediante Godot AI MCP. El inicio normal del proyecto sigue apuntando a Main.

| Acción | J1 | J2 |
|---|---|---|
| Movimiento | A / D | Flechas izquierda / derecha |
| Salto / doble salto | W | Flecha arriba |
| Descenso sobre naranja / caída controlada en aire | S | Flecha abajo |
| Ligero / fuerte | F / G | K / L |
| Defensa; con dirección horizontal, dash | H | Shift derecho |

R restablece los fixtures y jugadores. M alterna una trayectoria sintética reproducible: traslación de naranja y rotación de la estructura verde/naranja. El panel muestra contactos, rebotes, repeticiones evitadas, descensos, commits y diferimientos. Los IDs cortos identifican regiones; su estructura propietaria se conserva en datos y en el tooltip de la etiqueta.

El laboratorio contiene cinco estructuras lógicas y siete regiones: SOLID, BOUNCE, ONE_WAY, una unión verde/naranja y otra verde/azul. En la configuración inicial hay doce nodos de forma regional, siete habilitados; los restantes son bordes one-way deshabilitados por su orientación. El suelo auxiliar del laboratorio es fijo y está siempre presente: **no implementa todavía la futura regla SCENE_EMPTY**.

## Parámetros configurables

En `MaterialContactAdapter` (px, segundos, px/s):

| Parámetro | Valor inicial |
|---|---:|
| Impulso de rebote | 760 px/s |
| Impulso mínimo / máximo | 120 / 1000 px/s |
| Velocidad total máxima al rebotar | 1100 px/s |
| Retención tangencial | 0,35 |
| Separación para recuperar contacto | 3 px |
| Velocidad mínima inicial de descenso | 150 px/s |

En `MaterialPhysicsManager`: pendiente one-way máxima 46° (configurable entre 1 y 46°), margen nativo 1,5 px. Hereda límites de movimiento: 90 px/s lineal, 0,45 rad/s angular y 2 px de barrido superficial por paso. Los parámetros no cambian la gravedad original. Los valores de los adaptadores, creados en runtime, se pueden inspeccionar en el árbol remoto.

## Pruebas funcionales ejecutadas

Se utilizaron los CharacterBody2D reales y el servidor físico de Godot. Las posiciones iniciales controladas son fixtures del arnés; el código de materiales no teletransporta al personaje para resolver contactos.

| Caso solicitado | Comprobación ejecutada | Resultado final |
|---|---|---|
| 1 SOLID horizontal | Aterrizaje y apoyo real | FUNCIONA |
| 2 SOLID inclinado | Apoyo y normal a 0,25 rad | FUNCIONA |
| 3 SOLID cóncavo | Aterrizaje sobre silueta en L descompuesta | FUNCIONA |
| 4 SOLID con agujero | Personaje dentro del vacío y apoyo en su borde inferior | FUNCIONA |
| 5–8 BOUNCE arriba, abajo, izquierda y derecha | Lanzamiento y normal física, límites, sin daño | FUNCIONA |
| 9 BOUNCE diagonal | Normal más componente tangencial conservada | FUNCIONA |
| 10 BOUNCE inclinado | Normal rotada real a 0,35 rad | FUNCIONA |
| 11 Sin rebotes repetidos | Contacto continuo con impulso nulo de prueba; una activación y latch | FUNCIONA |
| 12 BOUNCE con dash | Interrupción de desplazamiento, invulnerabilidad conservada | FUNCIONA |
| 13 ONE_WAY desde abajo | Ascenso a través de región y aterrizaje posterior | FUNCIONA |
| 14 ONE_WAY lateral | Cruce de una cara lateral sin estado de pared | FUNCIONA |
| 15 Aterrizaje ONE_WAY | Apoyo horizontal, inclinado, cóncavo y borde de agujero | FUNCIONA |
| 16 Descenso con abajo | Excepción sobre apoyo naranja y velocidad descendente | FUNCIONA |
| 17 Recuperación | Sale de región, elimina excepción y vuelve a aterrizar | FUNCIONA |
| 18 Abajo en SOLID | Conserva apoyo, sin descenso ni excepción | FUNCIONA |
| 19 Verde/naranja | Una identidad lógica, dos cuerpos regionales, dos jugadores | FUNCIONA |
| 20 Verde/azul | Un jugador sostenido y otro rebotando independientemente | FUNCIONA |
| 21 Pose | Transporte SOLID y ONE_WAY; rotación ONE_WAY sin reconstrucción | FUNCIONA |
| 22 Geometría | Diferimiento ocupado y commit al abandonar la región | FUNCIONA |
| 23 Material | ONE_WAY→SOLID diferido durante cruce; SOLID→BOUNCE al contacto | FUNCIONA |
| 24 Jugador apoyado | Transporte medido y detención ante techo externo | FUNCIONA |
| 25 Dos jugadores | Contactos simultáneos con materiales diferentes | FUNCIONA |
| Estrés | 80 cambios repetidos de geometría/material/pose, sin crecimiento de nodos | FUNCIONA |
| Atomicidad | Miembro inválido rechaza lote, no crea el miembro válido; señal coherente | FUNCIONA |
| Estados | Defensa/ataque tienen prioridad sobre descenso; rebote conserva daño/hitstun | FUNCIONA |

**Dos pasadas headless: 142/142 cada una. Pasada gráfica lanzada mediante MCP: 142/142.** Incluyen aserciones repetidas de preparación/aplicación de fixtures; no son 142 mecánicas distintas. Tras ajustar las etiquetas se repitió la pasada gráfica.

Durante el desarrollo se detectó que `Input.parse_input_event` podía quedar encolado hasta render y perder la ventana `just_pressed` del tick esperado en headless. Se confirmó registrando tick y estado just-pressed. El arnés ahora inyecta acciones InputMap sincrónicas en un nodo de prioridad física anterior al Player. No se cambiaron criterios de aprobación ni controles del juego para ocultar los fallos.

### Métricas físicas y temporales

Resultados completos: `artifacts/phase3b2/pass1_result.json`, `pass2_result.json`, `mcp_result.json` y `summary.json`.

En cada pasada headless: 933 contactos registrados (incluyen el suelo auxiliar), 12 rebotes aplicados, 56 repeticiones evitadas, 2 descensos y 2 recuperaciones, 0 descensos retenidos más de 2 segundos. Hubo 1827 muestras de jugadores, **0 muestras con penetración sólida mayor a 1 px** y **0 pérdidas de apoyo durante movimiento** bajo el criterio instrumentado. La medición excluye el cruce intencional del volumen ONE_WAY. No equivale a demostrar error geométrico cero en cualquier escenario.

Transporte SOLID: apoyo **50/50 ticks**, error final de transporte **0 px**, máximo desplazamiento de personaje por tick **1,50004 px**. La geometría no se reconstruyó por ese movimiento.

Por pasada se aceptaron/aplicaron 120 lotes, se rechazaron 2 lotes inválidos intencionales y se difirieron 2 lotes ocupados. Se contabilizaron 124 reconstrucciones regionales, incluyendo fixtures, reinicios y los 80 cambios de estrés. Las verificaciones preventivas registraron 82 pasos con riesgo de penetración y 27 con obstáculo sólido externo; **son bloqueos preventivos, no penetraciones observadas ni errores del motor**. Las épocas cambian por los reinicios/reapariciones de fixtures. No se simularon MERGE/SPLIT nuevos en esta batería de materiales; sus suites anteriores se ejecutaron como regresión.

Tiempos del gestor material completo por tick, en el equipo actual:

| Ejecución | Muestras | Media ms | P50 ms | P95 ms | P99 ms | Máximo ms |
|---|---:|---:|---:|---:|---:|---:|
| Headless 1 | 1897 | 0,555 | 0,464 | 1,106 | 2,045 | 12,821 |
| Headless 2 | 1897 | 0,513 | 0,431 | 1,037 | 2,153 | 15,293 |
| Gráfica MCP | 1978 | 0,467 | 0,359 | 1,260 | 1,982 | 8,652 |

La validación lógica completa ocurre al enviar un estado y se mide aparte: en MCP, media 2,139 ms, P95 3,256 ms, P99 5,389 ms, máximo 12,556 ms. En la primera pasada headless hubo un máximo de **42,985 ms** (P99 27,035 ms); no se oculta ese pico. Commit físico MCP: media 0,656 ms, P95 1,459 ms, P99 2,558 ms, máximo 7,935 ms. Son cargas pequeñas sintéticas, no una prueba de capacidad máxima ni garantía de 60 FPS sostenidos. Física configurada y consultada en runtime: 60 ticks/s. Las métricas se guardan en buffers acotados.

No se registraron errores de script/física en las ejecuciones finales consultadas. Los logs de intentos fallidos del arnés se conservaron como diagnóstico, separados de los logs finales.

## Regresiones

| Suite realmente ejecutada | Resultado |
|---|---:|
| Juego original gráfico: menús, movimiento, combate, vidas, victoria, reinicio y caída controlada | 235/235 |
| Selección gráfica de personajes | 111/111 |
| UDP CAMERA/PROJECTOR anterior, integración gráfica | 37/37 |
| Selección headless | 92/92 |
| Fase 2A dash y ataques direccionales | 93/93 |
| Fase 1A polígonos dinámicos | 92/92 |
| Fase 1C geometrías compuestas | 110/110 |
| Fase 1D reproducción/adaptador offline | 127/127 |
| Nuevo protocolo UDP, validación Godot aislada | 160/160 |
| Contrato multimaterial Godot | 160/160 |
| Python: visión sintética, aislamiento de colores, homografía sintética, MERGE/SPLIT, geometría, offline, UDP y bootstrap con capturas falsas inyectadas | 147/147 |
| Controles del laboratorio mediante eventos de tecla M/R, movimiento sin reconstrucción y restablecimiento | 7/7 |
| Carga/parsing/instanciación e inicio físico de recursos Godot | 108 recursos, sin fallos |

El conjunto Python tardó 119,777 s. No abrió dispositivos físicos. La suite del protocolo UDP nuevo valida su transporte/contrato previo; **no conecta materiales con el receptor**. Godot AI MCP inspeccionó la jerarquía, referencias runtime y capas; ejecutó escenas, pruebas gráficas y capturas, y consultó los logs de las ejecuciones actuales. La captura final se encuentra en `artifacts/phase3b2/material_lab.png`.

Para repetir la nueva suite:

```powershell
& 'C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe' --headless --path 'C:\godot 4.6\juego frei\juegofrei' --script res://validation/MaterialPhysicsHeadless.gd
```

El resultado se escribe en `juegofrei/validation/material_physics_headless.json`. Las suites previas y sus logs se conservan en `artifacts/phase3b2/`.

## Limitaciones y pruebas humanas pendientes

- ONE_WAY soporta las caras superiores hasta la pendiente configurada; caras más empinadas se deshabilitan. No hay una superficie lateral ni inferior sólida naranja. Una rotación puede cambiar qué caras son transitables.
- El preflight de transporte y el margen de salida usan el rectángulo del Player actual. Cambiar posteriormente la forma física del personaje requiere extender esas comprobaciones; cambiar solamente sprites no lo afecta.
- StaticBody2D controlado externamente con pasos acotados no es un solucionador continuo de cuerpos rígidos. No se afirma estabilidad universal en rotaciones ocupadas, aplastamientos múltiples, contactos extremos o velocidades fuera de los límites. Se prioriza diferir/detener sobre forzar el movimiento.
- Los proxies preventivos ONE_WAY tienen 2 px de espesor; geometrías extremadamente finas pueden provocar diferimientos conservadores. No se comprobó toda combinación de agujeros, pendientes, bordes subpíxel y rotación.
- Se recortan bordes ONE_WAY enterrados; SOLID/BOUNCE conservan la descomposición convexa sin solapamiento interior del contrato. No se construyó un resolvedor personalizado de todas las costuras convexas posibles.
- Si otro sistema vuelve a mantener al jugador dentro de una región descendida, la excepción se conserva y se registra la retención; no se reactiva una colisión dentro del personaje a los dos segundos.
- El suelo auxiliar siempre presente y la reaparición local son del laboratorio. No se implementó aquí el ciclo de victoria/selección completo: se verificó en Main mediante regresión.
- Falta una sesión humana de dos jugadores que evalúe sensación de rebote, enlaces rápidos entre materiales, saltos/ataques sobre uniones y rotación ocupada. Las pruebas realizadas son sintéticas sobre física real, no una prueba física con objetos/cámara/proyección.
- Antes de aumentar cantidad de estructuras o frecuencia de cambios de silueta, perfilar el coste de validación completa y sus picos; no hay garantía medida de 60 FPS sostenidos.

## Recomendación para 3B.3

Con confirmación, conectar primero la extensión multimaterial al flujo de **reproducción offline** con snapshots completos, manteniendo este mismo adaptador y sus verificaciones. Ampliar escenarios de MERGE/SPLIT con un personaje sobre uniones entre materiales, presupuestos de coste y recuperación ante estados incompatibles. Después evaluar la conexión al transporte con límites y sesión ya existentes. No cambiar la geometría de las plataformas originales durante esa integración. Esta entrega se detiene en 3B.2; no inicia 3B.3.
