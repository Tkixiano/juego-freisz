# Fase 3C — Partida integrada con geometrías offline multimaterial

## Resultado

La partida normal ahora inicia en `res://scenes/IntegratedMatch.tscn`, configurada como main_scene. Usa exclusivamente regiones dinámicas SOLID, BOUNCE, ONE_WAY y el piso de seguridad condicional. Las tres plataformas anteriores **y el suelo permanente anterior** quedan sin capa/máscara, con su forma deshabilitada y ocultos en runtime.

No se eliminaron escenas ni archivos anteriores. `Main.tscn` queda como escena histórica para regresiones. Ejecutar F6 sobre esa escena histórica todavía reproduce el escenario anterior; F5 inicia la partida integrada.

No se modificó OpenCV, no se abrieron cámaras ni proyector y no se ejecutó cv2.VideoCapture. Los protocolos CAMERA/PROJECTOR y el transporte UDP de estructuras no cambiaron. La escena normal no instancia receptores UDP; las pruebas UDP se ejecutaron aparte.

## Arquitectura

1. **Fuente:** `OfflineReplayPlayer` existente reproduce los archivos v2 multimaterial de 3B.3. La opción vacía genera cinco estados completos sintéticos explícitos; no simula una desconexión.
2. **Frontera de escena:** `OfflineSceneGateway` valida el estado fuente, sesión, secuencia, contrato y estado del escenario. Aplica confirmación temporal y una traslación configurable para ubicar los fixtures en el escenario. Su API es `submit`, `set_health` y `request_reset`; un futuro receptor puede ocupar el lugar del reproductor sin conocer a los jugadores.
3. **Adaptación/física:** se reutilizan MaterialPhysicsAdapter, MaterialPhysicsManager, el backend transaccional y MaterialPolygonBody. No se agregó otro sistema de colisiones.
4. **Piso:** SafetyFloor es un StaticBody2D independiente, sin ID de estructura o región. Participa en el preflight del entorno, pero no en MERGE/SPLIT ni en los mapas OpenCV.
5. **Respawn:** SafeSpawn busca un espacio libre y superficies superiores del escenario; si no existe un lugar válido, espera sin descontar otra vida.
6. **Combate:** IntegratedGameManager hereda GameManager. Usa los Player, Combat, Damage, GameShell y selección de personajes existentes. El único ajuste al GameManager base elimina la dependencia obligatoria del controlador de mouse al reiniciar; no cambia reglas de daño/vidas.

El estado completo se valida antes de aplicar. El hook de entorno se ejecuta antes del commit físico, de modo que el piso y las regiones puedan intercambiarse en el mismo límite de física, sin un tick intermedio con ambos colisionando o sin el soporte previsto. Las rotaciones, concavidades y agujeros siguen usando el backend anterior.

La histéresis retiene eventos MERGE/SPLIT mientras confirma estados; no pierde el diagnóstico porque el evento haya ocurrido en el primer fotograma de la confirmación. Las regiones mantienen sus IDs y propietario lógico por el contrato de 3B.3.

## Estados y piso

| Estado | Comportamiento |
|---|---|
| Inicio sin estructuras | Piso disponible desde el arranque. |
| SCENE_EMPTY confirmado | Retira estructuras y activa el piso en una transacción segura. Si un jugador está debajo/dentro de la altura del piso, conserva el último escenario y difiere el cambio. |
| SCENE_ACTIVE confirmado | Aplica regiones. Retira el piso cuando ningún jugador depende de él y no hay conflicto físico. |
| SCENE_STALE | Conserva el último escenario y el estado actual del piso; congela movimiento de la geometría. No lo interpreta como vacío. |
| SCENE_ERROR | Conserva lo anterior. Un objetivo aún no aplicado se cancela, conservando los mapas e identidades ya comprometidos. |
| Recuperación | Confirma nuevos estados completos y vuelve a la aplicación transaccional. |
| Reinicio/cambio de fuente | Reinicia sesión/ledgers de la fuente, pero conserva la última geometría física hasta reemplazarla con un estado válido. |
| MERGE/SPLIT | Un único commit conserva las regiones y materiales; el piso no participa en la topología. |

El piso cubre X=-100 a X=1380, alineado con todo el ancho de los límites de eliminación, con cara superior en Y=580 y espesor 24 px. El HUD queda debajo del área de juego. Tiene colisión sólida normal en capa 1.

**Puede coexistir temporalmente con estructuras activas mientras su retirada esté diferida.** Esto es intencional: no se quita el apoyo a un jugador para forzar que desaparezca. No se vuelve a activar porque otras estructuras sean inaccesibles. Un jugador apoyado, descendiendo sin otro apoyo o intersectando su volumen impide retirarlo. Se reintenta en física; el motivo se muestra en el panel.

Si el objetivo nuevo intersectaría el piso, se difiere el lote completo mientras el piso sea necesario. Cuando ambos jugadores lo abandonan de forma segura, se deshabilita antes de publicar las formas nuevas. Si EMPTY exige crear un piso por encima de alguien, la transición también espera: no elimina el soporte inferior ni teletransporta al personaje.

### Parámetros

- Gateway: confirmación mínima **3 actualizaciones y 0,10 s** para ACTIVE/EMPTY. Ambas condiciones son necesarias.
- Offset de fixtures: **(300,180) px**, sólo sobre la pose global. No escala ni cambia geometría local. Para futuras coordenadas ya calibradas de arena deberá configurarse a cero, evitando una segunda transformación.
- Piso: Rect2 exportable; no depende de accesibilidad de regiones.
- Backend: conserva los límites de 3B.2: movimiento acotado, pendiente ONE_WAY hasta 46°, impulso de rebote y velocidad máxima configurables.
- La pausa/fin intencional de un archivo no es un timeout de red. El último estado confirmado permanece. Los estados STALE/ERROR pueden ser informados explícitamente mediante la API de fuente; no hay recepción de red en esta fase.

## Archivos

Existentes modificados:

- `juegofrei/project.godot`: nuevo main_scene.
- `juegofrei/scripts/GameManager.gd`: controlador de mouse opcional al reiniciar.
- `juegofrei/scripts/geometry/TransactionalGeometryManager.gd`: hook previo al commit, por defecto vacío.
- `juegofrei/scripts/material_physics/MaterialPhysicsManager.gd`: guard de entorno opcional.
- `juegofrei/scripts/material_physics/MaterialPhysicsAdapter.gd`: reinicio de fuente conservando geometría y cancelación de objetivos no aplicados conservando ledgers comprometidos.

Creados:

- `juegofrei/scenes/IntegratedMatch.tscn`.
- `juegofrei/scripts/integrated/IntegratedGameManager.gd`.
- `juegofrei/scripts/integrated/OfflineSceneGateway.gd`.
- `juegofrei/scripts/integrated/SafetyFloor.gd`.
- `juegofrei/scripts/integrated/SafeSpawn.gd`.
- `juegofrei/scripts/integrated/SceneSourcePanel.gd`.
- `juegofrei/validation/IntegratedMatchValidation.gd`.
- `juegofrei/validation/IntegratedMatchHeadless.gd`.
- `juegofrei/validation/Phase3COriginalRegression.gd`.
- Este informe y evidencias en `artifacts/phase3c/`.

La comparación SHA-256 de 101 archivos de producción iniciales detectó únicamente los cinco modificados enumerados. El controlador Player, sus recursos de gravedad/movimiento, combate, selección, OpenCV y protocolos conservaron sus hashes. Las suites regeneraron sus resultados JSON y capturas habituales.

## Cómo iniciar y elegir escenario

Abrir el proyecto normalmente y usar **F5 → Jugar → selección → LISTO de ambos jugadores**. Las selecciones independientes se conservan. Inicialmente hay piso y ninguna estructura.

En el panel superior de la partida:

- **ESCENARIO VACÍO CONFIRMADO:** seleccionarlo o pulsar Iniciar con esa opción genera la fuente vacía válida.
- **07_three.json:** una estructura con los tres materiales.
- **08_merge.json / 09_split.json / 27_orange_merge_split.json:** ejemplos de fusión y separación.
- **11_hole.json / 12_corner.json:** geometrías compuestas.
- **26_long.json:** secuencia prolongada.
- Iniciar, Pausar, Reiniciar fuente y Un estado controlan los datos. No reinician daño ni vidas. La pausa no pausa jugadores; ESC abre la pausa de partida.

Los archivos ya están presentes. Para regenerarlos, sin cámara:

```powershell
python -m vision.material_replay --long-frames 1800
```

Inicio por consola:

```powershell
& 'C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe' --path 'C:\godot 4.6\juego frei\juegofrei'
```

Controles conservados: J1 A/D, W, S, F/G, H; J2 flechas, K/L, Shift derecho. Arriba/abajo más ataque conserva los direccionales. Abajo sobre naranja permite descenso; sobre SOLID no lo atraviesa. F1 muestra controles. La selección conserva sus controles previos.

Se dejó abierta una partida mediante MCP con personajes Menta/Violeta y `07_three.json`: una estructura, tres regiones y tres vidas por jugador. Las cuatro colisiones antiguas están deshabilitadas. El piso permanece porque los jugadores están apoyados sobre él; el motivo es visible. Los IDs de región se ocultan en la partida para no tapar personajes; siguen disponibles en los datos/inspector y en los laboratorios.

También se verificó `project_run(mode="main")`, equivalente al arranque normal del editor. La selección se confirmó con entradas de teclado F/K simuladas mediante MCP. La primera comprobación detectó que el editor retenía Main.tscn en memoria; se detuvo el juego, se actualizó la escena principal mediante `set_main_scene` y se repitió el arranque. El runtime final confirmó `res://scenes/IntegratedMatch.tscn`, sin receptores UDP y sin errores actuales en los logs.

## Pruebas y resultados

La batería se amplió durante la integración: 43, 44, 49, 52, 53 y 57 comprobaciones antes del cierre. **La versión final pasó 59/59 headless y 59/59 mediante Godot AI MCP.** No se da por verificada por una única carga o un parsing sin errores.

Resultados finales coincidentes:

- 2004 estados recibidos por la frontera de fuente; 1287 encolados, 1286 aplicados, uno cancelado al interrumpir una operación aún no aplicada.
- 3 rechazos intencionales: duplicado, material inválido e identidad de evento inválida.
- 3 transacciones diferidas; 1 episodio de activación del piso diferida y 3 episodios de retirada diferida.
- 12 activaciones/12 retiradas del piso en toda la batería, **incluyendo los reinicios de fixtures**; no son 12 alternancias espontáneas de una sola partida.
- 6 solicitudes de respawn, una diferida por no existir espacio seguro; se recuperó al confirmar EMPTY sin descontar otra vida.
- 0 penetraciones sólidas mayores a 1 px: 1028 muestras activas de jugador headless y 1026 en MCP.
- 10 transiciones de apoyo totales por saltos, caídas y pruebas; **0 pérdidas de apoyo inesperadas asociadas a cambios ACTIVE** bajo el criterio instrumentado.
- MERGE apoyado: 53 ticks observados, cero pérdidas. SPLIT apoyado: 65 ticks, cero pérdidas. El piso ya estaba retirado en ambos casos.
- Reproducción prolongada: 1800 estados fuente consumidos, con 30 MERGE/29 SPLIT preservados. En el conjunto total hubo 32 MERGE/30 SPLIT.
- 143 reconstrucciones regionales en toda la batería; el estado final de la secuencia larga tenía una estructura, dos regiones y dos formas.

Los 719 registros HELD no son un conjunto disjunto de los aplicados: algunos estados se retienen por confirmación y su último snapshot se despacha posteriormente. Los estados fuente no confirmados mantienen el último escenario. No se afirma que todos los estados brutos se conviertan en reconstrucciones físicas.

El combate entre ambos jugadores produjo el intercambio esperado de 6 % por jugador. Se verificaron dash, ataques ascendentes/descendentes, rebote azul, descenso naranja, daño, pérdida de vidas, victoria y reinicio. El respawn rechazó posiciones ocupadas; no usa un teletransporte de recuperación para resolver actualizaciones de geometría.

### Comprobaciones finales

| Prueba automatizada | Resultado |
|---|---|
| initial_main_menu | FUNCIONA |
| selection_open | FUNCIONA |
| one_ready_waits | FUNCIONA |
| both_ready_start | FUNCIONA |
| selected_characters_kept | FUNCIONA |
| player_controls_kept | FUNCIONA |
| original_platforms_disabled | FUNCIONA |
| no_udp_nodes | FUNCIONA |
| initial_empty_floor | FUNCIONA |
| two_players_supported_by_floor | FUNCIONA |
| floor_is_not_structure | FUNCIONA |
| empty_source_play_button | FUNCIONA |
| stale_preserves_initial_floor | FUNCIONA |
| error_preserves_initial_floor | FUNCIONA |
| three_materials_active | FUNCIONA |
| floor_retirement_deferred_with_two_players | FUNCIONA |
| single_player_on_floor_keeps_it | FUNCIONA |
| safe_floor_retirement | FUNCIONA |
| stale_keeps_geometry_without_floor | FUNCIONA |
| error_keeps_geometry_without_floor | FUNCIONA |
| recovery | FUNCIONA |
| source_restart_preserves_support | FUNCIONA |
| new_source_recovers | FUNCIONA |
| confirmed_empty_restores_floor | FUNCIONA |
| empty_transition_no_stock_loss | FUNCIONA |
| single_active_detection_does_not_remove_floor | FUNCIONA |
| overlap_floor_batch_deferred | FUNCIONA |
| stale_cancels_only_unapplied_target | FUNCIONA |
| recovery_after_deferred_source_interruption | FUNCIONA |
| overlap_floor_retires_atomically_when_safe | FUNCIONA |
| blue_bounce_in_match | FUNCIONA |
| orange_from_below | FUNCIONA |
| orange_landing | FUNCIONA |
| orange_drop_in_match | FUNCIONA |
| active_inaccessible_does_not_activate_floor | FUNCIONA |
| dash_in_match | FUNCIONA |
| ascending_attack | FUNCIONA |
| descending_attack | FUNCIONA |
| two_player_combat | FUNCIONA |
| stock_loss_preserved | FUNCIONA |
| respawn_avoids_occupied_spawn | FUNCIONA |
| victory_preserved | FUNCIONA |
| restart_preserves_selection_and_stocks | FUNCIONA |
| duplicate_rejected | FUNCIONA |
| invalid_rejected_atomically | FUNCIONA |
| invalid_event_identity_rejected | FUNCIONA |
| ui_empty_source_confirmed | FUNCIONA |
| empty_activation_below_player_deferred | FUNCIONA |
| empty_activation_after_clearance | FUNCIONA |
| unsafe_respawn_waits_without_losing_stock | FUNCIONA |
| deferred_respawn_recovers_on_empty | FUNCIONA |
| 19_supported_merge_load | FUNCIONA |
| 19_supported_merge_native_support_in_match | FUNCIONA |
| 20_supported_split_load | FUNCIONA |
| 20_supported_split_native_support_in_match | FUNCIONA |
| long_replay_load | FUNCIONA |
| long_replay_complete | FUNCIONA |
| merge_split_in_match | FUNCIONA |
| no_measured_deep_penetrations | FUNCIONA |

### Métricas temporales

Milisegundos, percentiles empíricos del equipo actual:

| Pasada · etapa | Muestras | P50 ms | P95 ms | P99 ms | Máximo ms |
|---|---:|---:|---:|---:|---:|
| headless · gateway_validation | 2004 | 4.529 | 6.531 | 7.849 | 24.640 |
| headless · backend_validation | 1287 | 3.345 | 4.628 | 5.556 | 17.064 |
| headless · application | 1286 | 0.223 | 1.268 | 2.073 | 36.804 |
| headless · geometry_update | 2813 | 0.195 | 0.937 | 2.301 | 37.817 |
| mcp · gateway_validation | 2004 | 4.581 | 7.038 | 8.645 | 17.643 |
| mcp · backend_validation | 1287 | 3.366 | 5.069 | 6.071 | 13.658 |
| mcp · application | 1286 | 0.220 | 1.275 | 2.107 | 20.402 |
| mcp · geometry_update | 2812 | 0.216 | 0.963 | 2.202 | 21.822 |

Gateway incluye el coste del backend cuando despacha; sus percentiles no deben sumarse al backend como si fueran etapas independientes. Geometry_update incluye el preflight y commit del gestor, no el render completo ni toda la física de personajes. Hubo picos de aplicación de 36,804 ms headless y 20,402 ms MCP. **No se garantiza 60 FPS sostenidos.** La secuencia larga mantiene jugadores estacionados para aislar el escenario; el combate se prueba por separado. Son mediciones sintéticas sobre Godot real, no rendimiento de cámara/proyector ni una sesión humana prolongada.

Resultados completos: `final_headless_result.json`, `final_mcp_result.json`, `summary.json`, `compatibility.json` en `artifacts/phase3c/`.

## Regresiones ejecutadas

| Suite | Resultado |
|---|---:|
| Juego histórico gráfico: combate, menús, vidas, victoria, reinicio, movimiento y caída controlada | 235/235 |
| Selección gráfica | 111/111 |
| Selección headless | 92/92 |
| Fase 2A | 93/93 |
| Fase 1A | 92/92 |
| Fase 1C | 110/110 |
| Fase 1D, reproductor anterior | 127/127 |
| Física 3B.2 | 142/142 |
| Integración offline 3B.3 | 196/196 |
| Contrato multimaterial Godot | 160/160 |
| UDP anterior, escena histórica aislada | 37/37 |
| UDP nuevo, laboratorio de protocolo aislado | 160/160 |
| Python sintético, incluida Fase 1B, contratos, seguimiento y exportador | 152/152 |
| Carga/parsing/instanciación e inicio físico | 123 recursos sin fallos |

Los laboratorios conservan sus comportamientos anteriores porque los hooks nuevos son opcionales. Se consultaron logs de las ejecuciones actuales mediante MCP, se inspeccionó la escena y el estado runtime y se obtuvo `integrated_match.png`. Las advertencias históricas retenidas por el editor no se confundieron con errores de la ejecución actual.

Durante la primera ejecución apareció un acceso a manager nulo por el orden de ready de Replay/SceneSource. Se corrigió el orden de nodos y se repitieron las pruebas. También se protegió la recuperación de una fuente interrumpida con un lote diferido: se cancela sólo ese objetivo, conservando colisiones e identidades comprometidas. La prueba de interrupción/recuperación ahora pasa.

## Limitaciones y recomendación para 3D

- La política del piso es conservadora: puede permanecer mientras alguien se apoya o cae sin otra superficie. No se retira a la fuerza para que el escenario parezca vacío. Tampoco se reactiva por accesibilidad.
- EMPTY puede quedar diferido si alguien está debajo de la altura del piso. El panel muestra el motivo; la transición se reintenta al despejarse la zona. No se recoloca automáticamente a ese jugador.
- Si una geometría es inaccesible o queda fuera de los límites y no hay piso autorizado, un respawn puede esperar. Esto evita descontar vidas por un punto de reaparición inválido. Falta evaluar humanamente esa espera y su comunicación.
- La comprobación piso/región usa el volumen geométrico completo, incluso para ONE_WAY; puede diferir conservadoramente casos donde sólo una cara superior sería físicamente relevante.
- Se mantienen las limitaciones de StaticBody2D controlados externamente, pendientes ONE_WAY hasta 46°, geometrías extremadamente delgadas y rotaciones ocupadas. No se afirma estabilidad universal ante aplastamientos múltiples.
- Una operación diferida puede detener el avance del archivo hasta que sea segura. Cambiar/reiniciar fuente cancela objetivos pendientes sin borrar el último escenario válido.
- Falta una sesión humana de dos jugadores durante cambios rápidos de geometría y combates prolongados. No se utilizó hardware físico.
- Antes de Fase 3D: acordar límites de arena y política de conflicto persistente, perfilar los picos de validación bajo más regiones y conectar el receptor aislado a **esta misma frontera**. Se deben conservar sesiones, estados completos y la distinción EMPTY/STALE/ERROR; validar explícitamente la extensión multimaterial y sus épocas antes de llegar a física. Para coordenadas de arena ya calibradas, quitar el offset de fixtures.

**No se inició Fase 3D ni se conectó UDP al combate.**
