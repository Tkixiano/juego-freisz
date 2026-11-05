# Auditoría técnica y QA — Cubos / Arena

> Ajuste posterior de caída: el fast fall ahora tiene límite de 800 px/s, aceleración de 2100 px/s² y retorno progresivo a 640 px/s al soltar abajo (frenado 1800 px/s²). Se aprobaron 31/31 comprobaciones dirigidas en validation/controlled_fall_results.json. Las cifras de la auditoría y rendimiento que siguen corresponden a la versión auditada anteriormente.

Fecha: 20 de octubre de 2026. Motor verificado: Godot 4.6.3 estable oficial (7d41c59c4), Windows.

## Resultado

114/114 comprobaciones de la batería final aprobadas. Headless cargó, verificó parsing e instanció 30 recursos propios sin fallos. La última ejecución inspeccionada no registró errores ni advertencias en los logs del editor o del juego.

El prototipo conserva dos jugadores, movimiento y combate local, edición de plataformas durante la partida, gravedad de ascenso 1250 y descenso 1450 px/s², límite normal 640 px/s y fast fall 900 px/s. Las plataformas originales mantienen sus colliders, polígonos y escala; únicamente cambia su pose. No se agregó OpenCV, transporte UDP, webcam ni AR.

## Archivos de producción modificados

| Archivo | Cambio |
|---|---|
| scripts/GameShell.gd (nuevo) | Menú principal, controles, pausa, reanudación, reinicio y vuelta al menú. |
| scenes/GameShell.tscn (nuevo) | Interfaz con botones y navegación por teclado; capa de UI que sigue procesando durante la pausa. |
| scripts/UnstuckGuard.gd (nuevo) | Detección de solapamiento profundo persistente a 10 Hz y salida lateral segura; respawn de emergencia si no encuentra salida local. |
| scripts/PlayerController.gd | Reinicio de interpolación al reaparecer para evitar arrastre visual entre posiciones. |
| scenes/Player.tscn | Añadido UnstuckGuard a la escena reutilizable; las dimensiones del personaje y las plataformas no cambian. |
| scripts/DynamicPlatform.gd | Estado detected; detención de escritura de transformaciones en reposo; una última pose estacionaria elimina velocidad residual de transporte. |
| scripts/PlatformManager.gd | API de detección y consulta de estado, manteniendo sólo comandos de posición/rotación. |
| scripts/MousePlatformController.gd | Lectura de HUD a 10 Hz, rotación a 60 Hz y recuperación de detección por selección manual. |
| scripts/GameManager.gd | Actualización del HUD sólo cuando cambia el dato, referencias cacheadas, eliminación del filtro/array temporal por tick, integración del menú y HUD inicial correcto. |
| scripts/CombatEffects.gd | Procesamiento y redibujado desactivados cuando no hay ráfagas; se conserva el límite de 16. |
| scenes/Main.tscn | Instancia del menú y cámara fija configurada para procesamiento físico. |
| project.godot | Interpolación física, acciones Escape/F1 y nombre de capa Hurtboxes; se conserva Shift derecho físico. |
| README.md | Instrucciones actuales y enlaces a resultados de QA. |

Se añadieron validation/QAAudit.gd, validation/HeadlessAudit.gd y validation/PerformanceSampler.gd. Se ajustó validation/CombatValidation.gd para separar una captura de pantalla de una comprobación que depende de tiempos de combate. Los .uid y resultados JSON son archivos auxiliares generados.

## Errores corregidos y optimizaciones justificadas

1. Faltaban menú principal, controles y pausa. Ahora el juego inicia en el menú; Enter activa Jugar, Escape pausa/reanuda y F1 muestra controles. La pausa detiene actores, temporizadores de combate y plataformas. Tab sigue ocultando la edición sin pausar.
2. Faltaba detección en la API de plataformas. Perder detección congela la plataforma y conserva el collider; recuperar detección no reanuda un objetivo viejo. Los comandos de pose se rechazan mientras no hay detección. La selección manual restablece detección.
3. La parada de una plataforma requería vaciar la velocidad nativa de transporte. Se aplica una última transformación estacionaria antes de omitir las escrituras de reposo. La prueba adicional midió deriva de 0 píxeles del jugador durante la parada.
4. El caso real de techo invertido contra el suelo dejó al jugador atrapado en la primera implementación de recuperación vertical: produjo tres recuperaciones sin salir. Se corrigió la preferencia por salida lateral. La prueba final produjo una sola recuperación, dejó al jugador en (496, 542), estable sobre suelo, sin perder vidas ni modificar geometría.
5. Activar interpolación con la cámara en proceso idle generó una advertencia. La cámara fija ahora utiliza proceso físico; las reapariciones reinician la interpolación.
6. Se retiraron trabajo de HUD y efectos en reposo y asignaciones de arrays de jugadores por tick. La entrada y física continúan a 60 Hz. No se atribuye una ganancia porcentual de rendimiento: no se hizo una comparación A/B antes/después.

El UnstuckGuard consulta un rectángulo de prueba interior al jugador; no altera ninguna forma de escenario. Sólo interviene si el solapamiento profundo persiste 0,5 s. Busca poses libres y reinicia la interpolación tras recuperar. No concede una vida extra.

## Pruebas automatizadas ejecutadas

| Grupo | Comprobaciones |
|---|---:|
| api_guard_audit | 21 |
| combat_core | 15 |
| combat_defense | 11 |
| combat_stocks | 9 |
| gravity | 5 |
| movement | 17 |
| platform_carry | 8 |
| platform_combat | 5 |
| platform_limits | 7 |
| real_crush | 2 |
| ux | 14 |
| Total final | 114 |

Se comprobaron: movimiento simultáneo, aceleración/frenado, salto variable y doble salto, coyote time, buffer, control aéreo, límites de caída, descenso por plataformas, transporte lateral/vertical, rotación/inclinación, cruce de plataformas, límites lineales/angulares y del recorrido por tick, geometría inmutable, combate con escenario móvil, ataques ligeros/fuertes/aéreos y direcciones, dodge/cooldown, porcentajes, knockback, hitstun, daño único por activación, vidas, empate, victoria y reinicio.

La auditoría adicional comprobó referencias y señales de impacto/reaparición, separación de capas físicas y de combate, independencia de hitboxes, recurso de movimiento compartido, las 20 acciones del Input Map, Shift derecho físico, navegación de UI, pausa y vuelta al juego, rechazo de transformaciones con escala o datos no finitos, pérdida/recuperación de detección y prevención de penetración persistente.

Las entradas de las pruebas se inyectaron en el juego mediante Godot MCP (game_manage y game_eval/Input). No son pruebas realizadas por personas con un teclado físico.

### Headless

Comando ejecutado desde Codex:

`Godot_v4.6.3-stable_win64_console.exe --headless --path "C:\godot 4.6\juego frei\juegofrei" --script res://validation/HeadlessAudit.gd --log-file "../artifacts/headless_qa.log"`

Salida 0. Carga/parseo de 30 recursos .gd/.tscn/.tres, instanciación de Main, inicio en menú y cinco ticks de física después de iniciar partida. El modo headless no valida la apariencia ni mide FPS gráficos.

### Inspección visual

Se obtuvieron e inspeccionaron imágenes del menú principal, controles y pausa. La batería también genera una captura de victoria. Los archivos están en ../artifacts/qa_menu.png, qa_controls.png, qa_pause.png y combat_victory.png. Se revisaron jerarquías, nodos y referencias mediante el editor conectado. Las escenas abiertas se recargan desde disco para que no queden copias antiguas en memoria.

## Rendimiento medido en esta máquina

Muestra final: 45.012 s, tras 2 s de calentamiento. Dos luchadores con entradas programadas, tres plataformas moviéndose/rotando, ataques/saltos/dodges y 12 ráfagas de impacto por segundo. Sin capturas durante la muestra.

| Métrica | Resultado |
|---|---:|
| Cuadros medidos | 2701 |
| FPS promedio por reloj real | 60.006 |
| Tiempo de cuadro P50 | 16.663 ms |
| P95 | 17.180 ms |
| P99 | 17.588 ms |
| Máximo | 18.792 ms |
| Cuadros >25 / >33 / >50 ms | 0 / 0 / 0 |
| Monitor de procesamiento medio | 8.685 ms |
| Monitor de física medio | 1.806 ms |
| Nodos inicio / máximo / final | 84 / 84 / 84 |
| Huérfanos inicio / final | 0 / 0 |
| Memoria estática inicial | 54595198 bytes |
| Memoria estática máxima | 54611014 bytes |
| Memoria estática final | 54607486 bytes |
| Variación de memoria | 12 KiB |
| Draw calls máximas | 62 |

Los nodos incluyen el helper de depuración MCP y el muestreador temporal. No se instancian nodos por ataque/impacto. La estabilidad observada alcanza el objetivo nominal de 60 FPS en esta muestra; no demuestra ausencia de fugas a largo plazo ni garantiza el mismo resultado en otros equipos. Hay pequeñas variaciones de tiempo de cuadro; no se afirma que todos duren exactamente 16,667 ms.

## Preparación para OpenCV

IDs estables: left, right y top. Formas y dimensiones definidas en las escenas. El controlador de mouse depende del administrador; el administrador no depende de mouse, OpenCV, cámara ni red.

- get_platform(id)
- update_platform_position(id, Vector2): coordenadas del mundo en píxeles.
- update_platform_rotation(id, float): radianes.
- update_platform_transform(id, Transform2D): rechaza escala, skew, reflexión y valores no finitos.
- update_platform_detection(id, bool): actualiza detección sin eliminar o desactivar el cuerpo.
- get_platform_state(id): lectura de ID, posición, rotación y detección.

Un receptor futuro debe asociar cada módulo físico con estos IDs, convertir coordenadas/ángulos, marcar pérdida o recuperación de detección y enviar objetivos válidos. El suavizado y los límites continúan dentro de Godot. Reconocimiento, calibración, filtrado de detecciones y transporte externo quedan fuera de esta etapa.

## Pruebas manuales pendientes y limitaciones

- Partida con dos jugadores y una tercera persona usando hardware real: ghosting/rollover del teclado, ergonomía y percepción de latencia.
- Balance, sensación de gravedad/knockback y claridad visual durante partidas prolongadas.
- Sesión larga (30–60 minutos o más), otros equipos/GPU, distintas ventanas, pantallas y tasas de refresco.
- Exportación y ejecución de un .exe Windows distribuible: no se exportó en esta auditoría.
- OpenCV, webcam, UDP y AR no están implementados ni fueron probados.
- La recuperación de atrapamiento es una protección de emergencia: puede desplazar al personaje a una pose libre, o al spawn si no encuentra salida local. No sustituye pruebas exhaustivas de todas las configuraciones futuras.
- Inclinaciones superiores a 46° dejan de ser suelo para el personaje. Las plataformas siguen siendo unidireccionales y pueden cruzarse entre sí; no forman una simulación de cuerpos rígidos ni cambian de forma.
- No se dispone de pruebas de latencia de captura/proyección ni de reconocimiento de módulos porque esos sistemas no forman parte del prototipo.

## Evidencia

- validation/qa_results.json: batería final completa.
- validation/qa_edge_results.json: parada del transporte por pérdida de detección y aplastamiento real.
- validation/performance_qa.json: muestra de rendimiento final.
- validation/headless_qa.json y ../artifacts/headless_qa.log: comprobación headless.
