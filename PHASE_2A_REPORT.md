# Fase 2A — dash y ataques direccionales

Proyecto: `C:\godot 4.6\juego frei\juegofrei`. Godot AI MCP confirmó Godot **4.6.3-stable**, proyecto y runtime reales. Se inspeccionaron el controlador, movimiento, Input Map, dodge, perfiles de ataque, hitbox circular, resolución diferida de impactos y pruebas anteriores antes de editar.

Se reutilizan `PlayerController`, `CombatController`, `AttackData`, `CombatHitbox` y `GameManager`. No se implementó un segundo controlador. No se abrieron cámaras ni se usó proyector. No se modificaron OpenCV, UDP, Input Map, gravedad compartida ni arquitectura geométrica.

## Archivos modificados y creados

| Modificado | Cambio |
|---|---|
| `juegofrei/scripts/CombatController.gd` | Dash horizontal, cancelación descendente, serial de activación y feedback DASH |
| `juegofrei/scripts/PlayerController.gd` | Caída de ataque acotada y cancelación al apoyar después de `move_and_slide` |
| `juegofrei/scripts/AttackData.gd` | Velocidad inicial, límite y aceleración descendentes configurables |
| `juegofrei/scripts/GameManager.gd` | Invalidación de impactos encolados tras cancelación explícita |
| `juegofrei/resources/attacks/AirHeavy.tres` | Parámetros descendentes del fuerte |
| `juegofrei/scenes/GameShell.tscn` | Instrucciones nuevas y botón Volver separado del texto |

Creados: `juegofrei/validation/Phase2AValidation.gd`, `Phase2AHeadless.gd`, sus `.uid`, este informe y evidencia en `artifacts/phase2a/`.

La comparación SHA-256 de **79 archivos preexistentes** encontró solamente esos seis cambios. Permanecen intactos `PlayerMovement.gd`, `PlayerMovement.tres`, `project.godot`, los scripts/escenas de geometría, plataformas predefinidas y todos los archivos Python. No se editaron pruebas antiguas para hacerlas pasar.

## Mecánicas implementadas

### Dash

Izquierda/derecha + cubrirse produce un dash puramente horizontal desde suelo o aire. La dirección queda capturada y la velocidad se sobrescribe, nunca se acumula. Se reutiliza el estado DODGE y la curva decreciente del dodge anterior; el HUD muestra DASH.

Conserva máximo **580 px/s**, duración **0,30 s**, invulnerabilidad inicial **0,18 s** y cooldown **0,85 s**. Mantiene el límite de un dodge aéreo hasta tocar suelo. Un dash terrestre no consume por sí solo el uso aéreo.

Usa `move_and_slide`: una pared bloquea el desplazamiento sin teletransporte, mientras transcurre el tiempo restante de defensa. No se puede interrumpir con otro ataque, salto o dodge. Después de acabar la invulnerabilidad, un impacto aceptado puede interrumpirlo con hitstun. Se conservan las reglas anteriores de reaparición, eliminación y bloqueo de partida.

Sin dirección horizontal se mantiene la defensa previa: neutral inmóvil, o dodge vertical aéreo si se sostiene arriba/abajo.

### Ataque descendente

Se activa solo en aire con abajo + ligero/fuerte. Conserva los perfiles aéreos originales y fija el círculo en `(0, reach)`.

| Perfil | Daño | Startup / activo / recovery, frames | Radio / alcance px | Inicio / límite de caída px/s | Aceleración adicional px/s² |
|---|---:|---|---|---|---:|
| Aéreo ligero | 8 | 5 / 6 / 14 | 31 / 31 | 160 / 500 | 1.800 |
| Aéreo fuerte | 12 | 9 / 7 / 20 | 35 / 35 | 200 / 620 | 2.200 |

Al comenzar corta una eventual subida y establece descenso; no cambia la posición directamente. Su velocidad queda limitada por el perfil y `fast_fall_speed`. Si se caía más rápido, el ataque impone su límite. El movimiento especial dura durante el ataque; el daño existe **solo en sus active frames originales**, no indefinidamente hasta aterrizar. Al terminar vuelve la física normal.

Se cancela en el primer frame de apoyo registrado por `move_and_slide`, también si hay hitstop. Cubrirse lo cancela inmediatamente y después intenta iniciar la defensa normal. Si el cooldown, el uso aéreo o el hitstop la impiden, el golpe se cancela igualmente, sin conceder invulnerabilidad gratuita. No hay buffer nuevo de defensa: si queda bloqueada, requiere otra pulsación.

La cancelación aplica el cooldown del ataque, limpia sus víctimas e invalida su serial en la cola de impactos. No queda daño pendiente después de aterrizar o cubrirse. Recibir un golpe conserva la cancelación anterior, que permite los trades simultáneos normales.

Abajo + ataque desde suelo conserva el golpe bajo terrestre anterior; no activa la caída de ataque.

### Ataque ascendente

Arriba + ligero/fuerte fija el círculo en `(0, -reach)`. Conserva daño, radio, alcance, duración y perfil terrestre/aéreo. No agrega impulso vertical al atacante ni modifica su gravedad. La dirección y el lanzamiento se capturan al iniciar y no cambian al soltar o invertir las teclas.

Arriba sigue siendo la tecla de salto. Pulsarla antes puede iniciar el salto normal; el ataque no añade otro impulso. Cuando salto y ataque llegan juntos, el compromiso de ataque existente impide ejecutar ambos simultáneamente.

## Controles finales

| Acción | P1 | P2 |
|---|---|---|
| Movimiento | A / D | Izquierda / derecha |
| Salto / apuntar arriba | W | Arriba |
| Descenso / apuntar abajo | S | Abajo |
| Ligero / fuerte | F / G | K / L |
| Cubrirse | H | Shift derecho |
| Dash | A o D + H | Izquierda o derecha + Shift derecho |
| Ascendente | W + F/G | Arriba + K/L |
| Descendente aéreo | S + F/G | Abajo + K/L |

Esc pausa, F1 controles y R reinicio después de victoria. Mouse/Q/E/Tab y modos MOUSE/EXTERNAL conservados. Shift izquierdo sigue sin activar la defensa de P2. No se agregaron acciones al Input Map.

## Prioridades de entrada

| Situación | Regla |
|---|---|
| Apuntar ataque | Vertical prevalece sobre horizontal |
| Arriba + abajo | Se neutralizan para apuntar; ataque frontal según facing |
| Izquierda + derecha | Eje horizontal cero; no dash horizontal |
| Dodge con horizontal y vertical | Horizontal prevalece; vector sin componente vertical |
| Cubrirse + fuerte + ligero en neutral | Cubrirse, luego fuerte, luego ligero |
| Cubrirse durante descendente | Cancela primero; defensa sujeta a sus restricciones |
| Cubrirse durante otro ataque | No cancela; compromiso anterior conservado |
| Ataque durante dash/hitstun/respawn/hitstop/bloqueo | Rechazado según las restricciones existentes |
| Ataque durante cooldown | No se acumula ni se guarda; necesita una pulsación nueva |

La neutralización vertical describe la orientación del ataque, no cambia las reglas de salto/descenso normales. El dash tiene un tramo final vulnerable. Se conservan hitstop, transporte nativo de plataformas, salto variable, doble salto, coyote time, jump buffering y fast fall.

## Pruebas y resultados reales

| Suite | Resultado |
|---|---:|
| Fase 2A nueva, Godot MCP, dos pasadas | **93/93** en cada pasada |
| Fase 2A nueva, headless, repetida | **93/93** |
| Juego original completo, primera pasada MCP | **225/225** |
| Juego original completo, segunda pasada MCP | **225/225** |
| Receptor UDP anterior + mouse/combate | **37/37** |
| Polígonos Fase 1A | **92/92** |
| Geometría compuesta Fase 1C | **109/109** |
| Offline transaccional Fase 1D, headless | **127/127** |
| Python Fases 1B–1D, visión/calibración/UDP anterior | **110/110** |
| Carga/parsing headless | **69 recursos**, sin fallos |

La suite nueva cubre los 18 puntos solicitados: dash izquierda/derecha/aéreo, invulnerabilidad, cooldown, defensa neutral, descendentes y ascendentes ligeros/fuertes, orientación circular, ausencia de impulso ascendente, cancelación por suelo/plataforma/cubrirse, prioridades, recuperación y dos jugadores. Incluye impactos reales sobre el otro jugador, ausencia de daño duplicado, invalidez de daño encolado y trades simultáneos.

Superficies verificadas: suelo sólido, plataforma predefinida atravesable, polígono cóncavo creado con el administrador del laboratorio, superficie móvil y superficie inclinada. Sobre las cinco se verificaron aterrizaje/cancelación y dash manteniendo contacto. No se modificó el sistema geométrico para hacerlas funcionar.

Medidas de la segunda pasada gráfica: dash máximo **580 px/s** en ambas direcciones; descendente ligero **500 px/s** y fuerte **620 px/s**, alcanzados y acotados. El ascendente aéreo se comparó contra la integración normal `descent_gravity / 60` sin impulso añadido.

Una discrepancia inicial de prueba provenía de una pulsación de salto residual: elegía perfil aéreo al comprobar prioridad fuerte/ligero. Se estabilizó un tick durante el bloqueo normal de reaparición antes de preparar cada caso. No se cambió el juego para ocultarla.

La captura de controles detectó una regresión visual real causada por el texto añadido: Volver tapaba dos líneas. Se corrigió su posición y se verificaron los rectángulos reales por MCP: **sin superposición y dentro del viewport**. La segunda regresión completa se ejecutó después de esa corrección.

Los tests Python usan imágenes sintéticas y fábricas falsas de cámara. Los paquetes de regresión son loopback del protocolo anterior. No se usó webcam/proyector ni se transmitieron geometrías nuevas.

## Evidencia y reproducción

- `artifacts/phase2a/mcp_first.json`, `mcp_second.json`: resultados de las dos pasadas gráficas.
- `juegofrei/validation/phase2a_mcp.json`, `phase2a_headless.json`: filas individuales y medidas.
- `artifacts/phase2a/headless_final.txt`, `headless_final_repeat.txt`, `python_regression.txt`.
- `artifacts/phase2a/controls.png`, `controls_layout.json`: captura y comprobación de layout.
- `juegofrei/validation/full_phase2a.json`, `full_phase2a_second.json`, `udp_phase2a.json`.
- `artifacts/phase2a/phase1a.txt`, `phase1c.txt`, `phase1d.txt`, `load_final.txt`.
- `artifacts/phase2a/compatibility.json`, `summary.json`: huellas y resumen consolidado.

Desde `C:\godot 4.6\juego frei`:

```powershell
& "C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe" --headless --path juegofrei --fixed-fps 60 --script res://validation/Phase2AHeadless.gd
```

`--fixed-fps 60` controla la simulación; no mide FPS sostenidos. El juego se abre normalmente ejecutando `Main.tscn`.

## Limitaciones y recomendación para 2B

No hubo sesión física con dos personas ni medición de FPS/ghosting del teclado. El tacto de la duración/distancia de dash y la caída debe evaluarse jugando. Los descendentes conservan ventanas activas finitas y pueden terminar en aire; cubrirse no garantiza invulnerabilidad si sus restricciones lo impiden. La detección de apoyo sigue siendo la nativa del controlador existente.

No quedaron fallos reproducibles en las suites ejecutadas. Para 2B conviene ajustar parámetros y feedback mediante partidas humanas antes de agregar personajes o animaciones. Prolongar el daño descendente hasta aterrizar sería un cambio explícito de balance, con nuevas pruebas. **No se avanzó a Fase 2B.**
