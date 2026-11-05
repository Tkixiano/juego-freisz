# Cubos / Arena — combate local y escenario dinámico

Godot 4.6.3 · GDScript tipado · 1280 × 720 · física a 60 Hz · límite 60 FPS.

## Controles

- P1: A/D mover, W salto, S descenso y fast fall. F ligero, G fuerte, H dodge.
- P2: flechas izquierda/derecha mover, arriba salto, abajo descenso y fast fall. K ligero, L fuerte, Shift derecho dodge.
- Tercera persona: click izquierdo selecciona; arrastrar mueve; Q/E rota.
- Tab oculta/restaura la edición y sus resaltados, sin pausar a los jugadores.
- No hay comandos de tamaño, geometría, creación ni eliminación.

## Arquitectura

- Main.tscn conserva GameManager y los dos Player.tscn originales.
- Arena.tscn conserva el suelo; las plataformas son instancias de DynamicPlatform.tscn.
- IDs estables: left, right, top. Dos rectángulos de 230×18 y 280×24 y un trapecio convexo, definidos en las escenas.
- DynamicPlatform.gd realiza una única escritura de Transform2D por tick con sync_to_physics. Posición/rotación tienen objetivos suavizados, límite lineal 180 px/s, angular 0.70 rad/s, y recorrido máximo de superficie de 4 px/tick.
- PlatformManager.gd registra únicamente plataformas preexistentes. get_platform(id), update_platform_position(id, Vector2), update_platform_rotation(id, radianes), update_platform_transform(id, Transform2D).
- Los comandos devuelven false ante ID desconocido, valores no finitos o transformaciones con escala, skew o reflexión. Las posiciones se limitan al rectángulo configurable de cada plataforma.
- MousePlatformController.gd traduce eventos de viewport a coordenadas del mundo y envía comandos. No modifica geometría ni controla personajes.
- ExternalPlatformReceiver.gd recibe JSON por UDP local, valida IDs/secuencias y envía objetivos a PlatformManager. F2 o el botón del HUD alternan MOUSE/EXTERNAL. Sólo la fuente activa puede enviar comandos. Ver [EXTERNAL_INPUT.md](EXTERNAL_INPUT.md) para protocolo y simulador, y [el detector de visión](../vision/README.md) para webcam, OpenCV y calibración HSV. El receptor, el combate y la física no dependen de la fuente de visión.
- Para geometría irregular, el collider y el Polygon2D se definen juntos en el editor. La selección usa el contorno visual, sin asumir un rectángulo.

## Física de jugadores

Ambos jugadores comparten resources/PlayerMovement.tres. Ajustar allí ascenso (1250 px/s²), descenso (1450), impulso de salto (650 px/s), doble salto (620), caída máxima (640), fast fall (800), su aceleración (2100) y el frenado al soltar abajo (1800 px/s²). Mantener S/↓ acelera suavemente; soltar vuelve progresivamente al límite normal sin un corte brusco. Se conservaron los parámetros de movimiento horizontal, coyote y buffer.

Se midió una caída de 200 px en 0.533 s; referencia analítica anterior con 1850 px/s²: 0.465 s. El salto completo alcanzó su ápice en aproximadamente 0.55 s y sigue alcanzando las plataformas laterales. El fast fall acelera progresivamente.

Se usa el transporte nativo de CharacterBody2D sobre AnimatableBody2D, con snap de 8 px y conservación de impulso ascendente al saltar. Referencia: https://docs.godotengine.org/en/4.6/classes/class_animatablebody2d.html

Las plataformas conservan colisión unidireccional: se atraviesan desde abajo y permiten descenso voluntario. Pueden cruzarse entre sí sin bloquearse; no colisionan con el suelo como cuerpos dinámicos. En inclinaciones mayores que 46° el personaje pierde el apoyo y cae: no se adhiere a paredes ni plataformas invertidas.

## Validación ejecutada por Godot MCP

validation/dynamic_results.json contiene 37 comprobaciones aprobadas: 8 de transporte/colisión, 7 de API/límites/cruce, 5 de gravedad y 17 de regresión de jugadores.

También se inyectaron eventos reales de mouse mediante input_mouse: selección de left, arrastre de (385,435) a (465,405), liberación y verificación del objetivo alcanzado. Una secuencia de entradas probó rotación y desplazamiento simultáneo de ambos jugadores. Se inyectó Tab para comprobar ocultar/restaurar la interfaz sin pausa.

Los scripts de validación permanecen en validation/. Son utilidades de prueba; no se ejecutan al iniciar la partida. Sus funciones asíncronas largas se lanzaron desde game_eval conservando la instancia en metadatos del Main y consultando los resultados posteriormente, para respetar el límite de ocho segundos por evaluación MCP.

No se exportó un ejecutable Windows. No hay pruebas de sensación realizadas por una persona: ese ajuste subjetivo queda disponible sobre el recurso compartido.

## Combate local

Tres vidas por jugador. El porcentaje aumenta con cada impacto y se reinicia al perder una vida. Fuera de los límites se pierde una vida; con cero se elimina al personaje y se muestra la victoria. Las últimas vidas perdidas en el mismo tick producen empate. R reinicia la partida conservando la disposición de plataformas elegida por la tercera persona.

- CombatController.gd administra ataques, dodge, hitstun, invulnerabilidad e hitstop; DamageModel.gd contiene porcentaje, vidas y cálculo de lanzamiento.
- PlayerController.gd arbitra los estados Idle, Run, Jump, Fall, Attack, Dodge, Hitstun, Respawn y Eliminated. El movimiento básico conserva el mismo PlayerMovement.tres.
- Los cuatro recursos en resources/attacks/ son perfiles compartidos de ataque; cada activación mantiene su propio reloj y conjunto de víctimas.
- Light: 4/4/12 frames de startup/active/recovery, 6% de daño. Heavy: 12/5/24, 14%. AirLight: 5/6/14, 8%. AirHeavy: 9/7/20, 12%. A 60 ticks/s. Cooldown adicional predeterminado 0.08 s.
- Mantener la dirección de salto o descenso al iniciar un ataque selecciona arriba/abajo. En el aire, el fuerte hacia abajo lanza hacia abajo; el ataque sin dirección usa la orientación horizontal del personaje. El movimiento lateral establece esa orientación.
- Knockback = fuerza base × (1 + porcentaje posterior al golpe × crecimiento) × multiplicador, limitado por maximum_knockback. Ángulos, daño, tamaño, alcance, tiempos e hitstun están exportados en AttackData.
- Hitbox consulta únicamente áreas de hurtbox en la capa 8 (bit 4), con exclusión propia y una víctima como máximo por activación. Las colisiones de escenario se conservan en las capas 1 y 2.
- Dodge: duración 0.30 s, invulnerabilidad 0.18 s, cooldown 0.85 s. Una esquiva aérea antes de volver a tocar suelo. Se combina con dirección; sin dirección es una esquiva en el lugar.
- Reaparición: bloqueo breve de 0.45 s e invulnerabilidad de 2 s. Invulnerabilidad tras impacto: 0.12 s.
- Hitstop local de 3 o 5 ticks: detiene el reloj y el desplazamiento propio de ambos luchadores implicados. Mantiene el transporte nativo de plataformas; ni el árbol ni el administrador de plataformas se pausan.
- CombatEffects.gd dibuja destellos/partículas geométricas en un conjunto acotado de 16 ráfagas. El dodge y la invulnerabilidad tienen contornos propios; no se instancian nodos por impacto.
- Shift derecho está registrado en InputMap por physical_keycode y location=2. En Godot 4.6.3, la comparación de ubicación se aplica a la tecla física: https://github.com/godotengine/godot/blob/4.6.3-stable/core/input/input_event.cpp#L521

## Validación de combate

validation/combat_results.json registra 76/76 comprobaciones aprobadas. Incluye impactos ligeros/fuertes/aéreos, direcciones, daño único, crecimiento de knockback, hitstun, estados incompatibles, hitstop, dodge/cooldown/invulnerabilidad, distinción de Shift, vidas, señales, empate, victoria y reinicio. Se repitieron las pruebas anteriores de movimiento, transporte y gravedad.

Se simularon mouse, salto y ataques de ambos jugadores mientras una plataforma se trasladaba y rotaba. Se inspeccionaron visualmente las capturas de impacto y victoria guardadas en ../artifacts/. Las pruebas largas se ejecutaron de forma asíncrona mediante game_eval y se consultaron después de completarse.

No se agregó cambio de forma/tamaño de plataformas, servicios externos ni assets externos. Queda disponible el ajuste subjetivo de balance mediante los recursos exportados.

## Auditoría final y navegación

El proyecto inicia en el menú principal. Enter o Jugar inicia la partida. Esc pausa/reanuda; F1 abre controles. La pausa ofrece reinicio y vuelta al menú. Tab sigue ocultando la interfaz de plataformas sin pausar.

Se agregó detección a PlatformManager (update_platform_detection/get_platform_state), parada estable de cuerpos, interpolación y recuperación lateral ante atrapamiento persistente. Las formas y tamaños originales se conservan.

La auditoría final aprobó 114/114 comprobaciones, carga headless de 30 recursos y una muestra gráfica de 45 s a 60,006 FPS promedio (P99 17,588 ms). Son mediciones de esta máquina, no garantías para otros equipos.

Ver [QA_REPORT.md](QA_REPORT.md) para archivos modificados, errores corregidos, metodología, resultados y pruebas manuales pendientes.
