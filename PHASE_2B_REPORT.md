# Fase 2B — selección de personajes y presentación visual

Proyecto: `C:\godot 4.6\juego frei\juegofrei`, Godot **4.6.3**. Trabajo validado en el editor/runtime mediante Godot AI MCP y pruebas headless. Sin cámaras, proyector, spritesheets definitivas, cambios de OpenCV o protocolos UDP.

## Arquitectura

`Main.tscn` ya instancia dos `Player.tscn`. Se conservan esos dos CharacterBody2D, sus IDs, controles, movimiento y combate. Al iniciar una partida se instancia **la escena visual elegida** dentro de cada cuerpo, sin reconstruir el controlador ni sus colisiones. Reiniciar con la misma selección no agrega nodos ni conexiones.

- `CharacterDefinition.gd`: Resource con ID estable, nombre, retrato opcional, escena visual, SpriteFrames, mapa de animaciones, color/estilo provisional, escala y offset visuales. No contiene estadísticas ni dimensiones físicas.
- `CharacterCatalog.gd`: cuatro Resources: **Índigo, Ámbar, Menta y Violeta**. Los cuatro comparten movimiento, ataques, daño, vidas, dash y reglas originales.
- `CharacterPresentation.gd`: adaptador hijo del Player. Lee estados del controlador existente y actualiza la apariencia. No escribe velocidad, daño, controles o formas físicas.
- `CharacterAppearance.tscn` / `.gd`: escena visual estándar con AnimatedSprite2D y fallback geométrico. Permite cambiar a SpriteFrames sin modificar menú ni combate.
- `CharacterSelect.tscn` / `.gd`: dos selecciones independientes, cuatro entradas por jugador, confirmación, cancelación y navegación.

Los cubos provisionales tienen colores y símbolos diferentes. En combate el identificador muestra **P1/P2 y nombre**; el color de equipo original se conserva para distinguir a dos jugadores que elijan el mismo personaje. Cada uno tiene su propia instancia visual y material de feedback.

La escena visual se valida antes de agregarla al árbol: escenas que no cumplen la interfaz o contienen CollisionObject2D, CollisionShape2D o CollisionPolygon2D se reemplazan por el fallback. Escala/offset se aplican únicamente al arte, nunca al cuerpo, hurtbox o hitbox.

## Flujo y controles

**Menú principal → Jugar → Selección → ambos LISTO → partida.**

Cada columna permite elegir cualquiera de los cuatro, incluido el mismo personaje que el otro jugador. Confirmar uno no inicia la partida. Mientras un jugador está listo no puede cambiar de entrada; debe cancelar primero. Al estar ambos listos se inicia automáticamente una sola partida.

| Acción de selección | J1 | J2 |
|---|---|---|
| Anterior / siguiente, con vuelta circular | A / D | Izquierda / derecha |
| Confirmar LISTO | F | K |
| Cancelar LISTO | H | Shift derecho |
| Elegir / confirmar / cancelar | Mouse en su columna | Mouse en su columna |
| Volver al menú | Esc o botón Volver | Esc o botón Volver |

Shift izquierdo no cancela la confirmación de J2. Las flechas no desplazan foco de botones de J1: la selección consume las acciones del jugador antes de la navegación GUI general. F1 permite consultar controles y volver a selección. El inicio limpia acciones y conserva el bloqueo normal de reaparición para que confirmar con F/K no provoque golpes involuntarios.

Pausa → Continuar o Reiniciar mantiene los personajes confirmados. Para cambiar entre partidas: volver al menú principal y pulsar Jugar. Se recupera la pareja confirmada como punto de partida, pero ambos deben confirmar otra vez. Cancelar y volver al menú no confirma una elección nueva. La selección se conserva en la sesión; no se guarda entre cierres de la aplicación.

No se agregó ninguna acción al Input Map ni se reasignaron dispositivos/IDs. En combate se mantienen A/D/W/S/F/G/H para P1 y flechas/K/L/Shift derecho para P2, junto con todas las mecánicas de Fase 2A.

## Configurar un personaje

Editar uno de `res://resources/characters/{Indigo,Amber,Mint,Violet}.tres`:

| Campo | Uso |
|---|---|
| `character_id` | ID estable y único en el catálogo |
| `display_name` | Nombre mostrado |
| `portrait` | Texture2D opcional; si falta se muestra el preview geométrico/animado |
| `visual_scene` | Por defecto `res://scenes/CharacterAppearance.tscn` |
| `sprite_frames` | SpriteFrames propio del personaje; puede quedar vacío |
| `animation_map` | Estado lógico → nombre real del clip |
| `accent`, `placeholder_style` | Color y símbolo provisionales |
| `visual_scale`, `visual_offset` | Ajuste del arte respecto del cuerpo, sin cambiar física |

Para cambiar una de las cuatro entradas se modifica su Resource. El catálogo centraliza las referencias; no hay cuatro copias de PlayerController o CombatController.

## Incorporar una spritesheet posteriormente

Esta fase **no importa arte definitivo**. Cuando esté disponible:

1. Crear un Resource `SpriteFrames` para ese personaje.
2. Agregar sus clips con sus nombres reales, cantidad de frames, FPS, duración por frame y loop correspondientes.
3. Cada frame puede ser una Texture2D individual o una AtlasTexture con su propia región. No se exige una grilla común ni tamaños iguales entre frames o personajes.
4. Asignar el SpriteFrames al campo `sprite_frames` del CharacterDefinition.
5. Configurar `animation_map`, `visual_scale` y `visual_offset` para alinear el arte. Usar padding/márgenes de atlas si los pivotes varían entre fotogramas.

Estados lógicos preparados:

| Estado | Significado |
|---|---|
| `idle` | Reposo |
| `run` | Caminar/correr |
| `jump`, `fall` | Subida y caída |
| `light`, `heavy` | Golpe ligero/fuerte |
| `up`, `down` | Ataque ascendente/descendente |
| `dash` | Dash/dodge existente |
| `hurt` | Hitstun/recibir daño |
| `defeat` | Eliminación |

Ejemplo de mapa: `{"idle":"Reposo_A", "run":"Caminar_B", "light":"Golpe_01", "up":"AtaqueAlto"}`. Las velocidades se configuran por clip en SpriteFrames; no están hardcodeadas en el controlador.

Si falta el clip solicitado se intenta el idle mapeado. Si también falta o no tiene frames, aparece la geometría provisional. Ninguna animación se espera para resolver impactos, cancelar ataques, reaparecer o terminar una partida. Las animaciones de una sola reproducción no se reinician cada tick después de acabar.

El flash y la transparencia de invulnerabilidad están preparados también para sprites. El material usa el color ya texturizado de CanvasItem, evitando multiplicar dos veces la textura, según la [referencia oficial de CanvasItem shaders](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/canvas_item_shader.html). Se verificaron color, flash blanco y alpha con una textura sintética temporal en el runtime real.

Una escena visual personalizada debe ser Node2D, sin nodos físicos, e implementar `configure(definition)` y `apply_visual_state(state, facing, flash)`. Sus scripts y tracks deben permanecer en el subárbol visual. Para el flujo habitual de SpriteFrames basta con conservar la escena estándar.

## Pruebas y evidencia

La suite nueva prueba los 16 puntos solicitados y comprobaciones adicionales:

- Abrir selección, recorrer los cuatro, independencia de entradas, misma elección y confirmación/cancelación por jugador.
- Impedir inicio con uno solo listo; comenzar con ambos; comprobar que los recursos/instancias corresponden a la elección.
- Conservar IDs/acciones, limpiar la entrada de confirmación y cambiar de personaje entre partidas.
- Golpes ligeros/fuertes, dash, daño, derrota, respawn y reinicio con cada uno de los cuatro.
- Colisiones, hurtbox, hitbox, escala del cuerpo y recurso de movimiento sin cambios por apariencia.
- Portrait configurable, fallbacks de todos los estados y ausencia de spritesheets definitivas.
- Clips con nombres, tamaños de frame y FPS distintos; no reiniciar one-shots; materiales independientes.
- Mouse real sobre tarjetas, LISTO/cancelación y Volver; píxeles del preview siguen la elección.
- Textura sintética renderizada con color correcto, flash blanco y alpha heredado.

Los recursos de textura usados para esas pruebas se crean **solo en memoria**; no son spritesheets importadas ni arte definitivo.

| Validación realmente ejecutada | Resultado |
|---|---:|
| Suite nueva gráfica, Godot MCP | **111/111** |
| Suite nueva headless, dos pasadas finales | **92/92** cada una |
| Juego completo con navegación actualizada, dos pasadas MCP | **235/235** cada una |
| Fase 2A: dash y ataques | **93/93** |
| Fase 1A: polígonos | **92/92** |
| Fase 1C: compuestos/agujeros | **109/109** |
| Fase 1D: offline transaccional | **127/127** |
| Python: visión sintética, calibración y fases 1B–1D | **110/110** |
| UDP anterior, mouse y combate | **37/37** |
| Auditoría headless de carga/parsing | **82 recursos**, sin fallos |

Resultados consolidados y archivos: `artifacts/phase2b/summary.json`, `mcp_final.json`, `headless_final.txt`, `headless_repeat.txt` y `juegofrei/validation/phase2b_{mcp,headless}.json`. La auditoría de carga aprobada está en `load_retry.txt`: un intento anterior no pudo escribir su archivo de reporte; se liberó el arnés pendiente y se repitió secuencialmente con éxito. No se confundió ese intento con un resultado aprobado.

Las pruebas originales de navegación se actualizaron para confirmar ambos LISTO después de Jugar: el flujo anterior de inicio inmediato ya no era el comportamiento solicitado. Se conservaron sus comprobaciones de combate/movimiento y se añadieron diez aserciones, pasando de 225 a **235 comprobaciones**. No se utilizó un bypass de selección en las interacciones GUI; los reinicios internos de las pruebas de física conservan su API anterior.

Regresiones: juego completo, Fase 2A, laboratorios 1A/1C/1D, Python de visión/1B/offline y UDP anterior. Consultar el resumen para las cantidades finales y la segunda pasada. Los paquetes de regresión son loopback del protocolo existente; no hay cámaras físicas ni geometrías nuevas transmitidas por red.

La comparación SHA-256 de **79 archivos preexistentes de producción/Python** muestra solo cuatro cambios de producción: GameManager, GameShell y las escenas GameShell/Player. PlayerController, CombatController, AttackData, recursos de ataques/movimiento, formas de colisión, plataformas, Input Map, OpenCV y protocolos se conservaron. Las dos pruebas de navegación adaptadas se enumeran aparte.

Durante las iteraciones se corrigió la invalidación del preview al cambiar Resource. También se estabilizó la captura GPU de una textura recién creada y se corrigió un acceso a Resource constante en la prueba de portrait. Las ejecuciones fallidas se conservan; no se cuentan como verificaciones aprobadas.

## Archivos

Producción modificada:

- `juegofrei/scripts/GameManager.gd`: selección de Resources y aplicación visual al iniciar/reiniciar.
- `juegofrei/scripts/GameShell.gd`: página SELECTION y flujo de confirmación.
- `juegofrei/scenes/GameShell.tscn`: instancia de CharacterSelect.
- `juegofrei/scenes/Player.tscn`: hijo Presentation, sin cambios en colisiones/controlador.

Pruebas anteriores adaptadas: `validation/QAAudit.gd` y `FunctionalAudit.gd`, por el nuevo flujo intencional.

Creados: cinco scripts `CharacterDefinition.gd`, `CharacterCatalog.gd`, `CharacterAppearance.gd`, `CharacterPresentation.gd`, `CharacterSelect.gd`; escenas `CharacterAppearance.tscn` y `CharacterSelect.tscn`; cuatro Resources en `resources/characters/`; `validation/Phase2BValidation.gd`, `Phase2BHeadless.gd`; sus `.uid`, este informe y evidencia.

## Ejecutar y límites

```powershell
& "C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe" --headless --path juegofrei --fixed-fps 60 --script res://validation/Phase2BHeadless.gd
```

La ejecución headless omite comprobaciones de mouse/píxeles y no mide FPS. Las pruebas gráficas se ejecutan por MCP en Main.tscn. Al entregar se deja la selección abierta y la simulación de combate pausada para inspección.

No se verificó arte final, alineación de sus pivotes, una partida física de dos personas ni rendimiento máximo del hardware. El estado `defeat` está mapeado, pero se conserva la ocultación original del cuerpo al eliminarse fuera de arena; no se agregó una espera de animación ni una nueva regla de derrota. El fallback visual nunca retrasa el resultado.

No se alteraron combate, gravedad, plataformas, hitboxes ni protocolos para implementar apariencias. No se avanzó a importar spritesheets definitivas ni a otra fase.
