# Fase 3B.3 — Integración offline multimaterial

## Resultado y arquitectura

Se conectó la segmentación y seguimiento multimaterial Python con la física Godot mediante **estados completos en archivos locales**. No hay conexión de UDP con las físicas, ni captura de cámara, ni proyección.

`MaterialReplayExporter` reutiliza `MaterialStructures`, sus contratos compuestos y el seguimiento existente. El mismo `OfflineReplayPlayer` lee v1/v2 y entrega los estados a `MaterialPhysicsAdapter`, que hereda `OfflineGeometryAdapter`. Se reutilizan exactamente el gestor transaccional, los StaticBody2D regionales y el adaptador de contactos de 3B.2. No se construyó otro sistema de colisiones.

La escena nueva hereda el código del laboratorio físico: dos Player.tscn originales, movimiento, combate y resolución de impactos existentes. No modifica Main ni sus plataformas. El laboratorio usa un suelo auxiliar a Y=570 para que las siluetas sintéticas ubicadas alrededor de Y=300 sean alcanzables con los saltos existentes; no implementa la regla futura de piso por SCENE_EMPTY.

El adaptador ahora expone diferencias lógicas y regionales: altas, retiros, pose, geometría, material, propietario y regiones sin cambios. Las épocas regionales se validan explícitamente; una región puede cambiar de estructura durante MERGE/SPLIT sin cambiar artificialmente de identidad. La sesión no cambia sin reset explícito. Las épocas y versiones anteriores no sobrescriben estados posteriores.

El estado completo se valida antes de modificar cuerpos. Un lote inválido se rechaza; una actualización que encerraría al jugador queda diferida. La publicación lógica y regional es atómica y se verificó mediante un observador de cada commit. No se crea un collider para la silueta lógica completa: sólo existen las colisiones de sus regiones, evitando un SOLID invisible sobre naranja.

## Archivos

Modificados respecto del inicio de esta fase:

- `juegofrei/scripts/geometry/OfflineReplayPlayer.gd`: lectura v2, sesión de archivo y migración opcional.
- `juegofrei/scripts/material_physics/MaterialPhysicsAdapter.gd`: sesión, épocas regionales, diferencias lógicas y migración v1→SOLID.

Creados:

- `vision/material_replay.py`.
- `tests/test_material_replay.py`.
- `juegofrei/scripts/material_physics/MaterialOfflineLab.gd`.
- `juegofrei/scenes/MaterialOfflineLab.tscn`.
- `juegofrei/validation/MaterialOfflineValidation.gd`.
- `juegofrei/validation/MaterialOfflineHeadless.gd`.
- `juegofrei/validation/MaterialOfflineCombatValidation.gd`.
- `juegofrei/validation/Phase3B3OriginalRegression.gd`.
- `MATERIAL_REPLAY_V2.md` y este informe.
- 27 reproducciones y manifiesto en `juegofrei/validation/material_replays/`.
- Evidencias, resultados y capturas en `artifacts/phase3b3/`.

Las suites regeneraron también sus JSON/capturas habituales. El archivo `header_bad.json`, fuera del manifiesto, es un caso inválido generado por las pruebas.

La comparación SHA-256 con la línea base confirmó que sólo cambiaron los dos scripts de producción enumerados. Los módulos OpenCV previos, protocolos UDP, movimiento, gravedad, combate, menús y plataformas originales conservaron sus hashes. El nuevo módulo Python sólo agrega exportación; no modifica segmentación ni seguimiento.

## Formato y ejecución

Especificación completa: `MATERIAL_REPLAY_V2.md`. El archivo usa `replay_version: 2`, contrato geométrico v1 y extensión material v1. Incluye sesión, secuencia, tiempo lógico, estructuras completas, épocas lógicas/regionales, poses, geometría local, versiones, confianza, seguimiento y eventos. Los mensajes no son sólo diferenciales.

El lector anterior conserva los archivos v1. El laboratorio multimaterial migra cada estructura v1 a una región SOLID con ID determinista; un backend antiguo rechaza v2 explícitamente, en vez de perder los materiales.

Desde la raíz del proyecto:

```powershell
python -m vision.material_replay --long-frames 1800
```

Para regenerar solamente un escenario conservando los demás:

```powershell
python -m vision.material_replay --scenario 27_orange_merge_split
```

La generación completa incluye **2601 estados y 27 escenarios**. El escenario largo contiene 1800 estados: 60 segundos lógicos a 30 Hz. La reproducción de prueba usa 2× y nunca omite estados para acelerar.

Abrir `res://scenes/MaterialOfflineLab.tscn` y ejecutar la escena con F6. También:

```powershell
& 'C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe' --path 'C:\godot 4.6\juego frei\juegofrei' res://scenes/MaterialOfflineLab.tscn
```

La interfaz permite elegir archivo, reproducir, pausar, reiniciar, avanzar un estado y seleccionar 0,25×/0,5×/1×/2×. Muestra contadores, conflictos, rebotes/descensos, eventos y el último error del lector. El tooltip de estadísticas conserva detalles de eventos/errores. Pausar los datos no pausa jugadores ni combate. Reiniciar reinicia los datos; seleccionar archivo también reaparece a los jugadores.

Controles conservados: J1 A/D, W, S, F/G, H; J2 flechas, K/L y Shift derecho. Abajo permite descender sobre naranja. R reinicia la reproducción. El inicio normal del proyecto continúa en Main.

## Validación funcional

Se completaron pasadas iniciales de 163, 171, 186 y 190 aserciones mientras se ampliaba la batería. La versión final pasó **196/196 headless y 196/196 mediante Godot AI MCP**, sin fallos. Las aserciones incluyen carga/preparación de fixtures; no representan 196 mecánicas distintas.

Se verificaron creación, retiro, reaparición, agujeros, concavidades, esquina, uniones de materiales, pose, geometría, material, duplicados, orden, sesión, épocas de región y raíz, migración v1, rechazo v2 en backend antiguo y recuperación con snapshots completos. Movimiento, rotación y los dos materiales móviles construyeron una sola geometría inicial cada uno: sus poses posteriores no reconstruyeron formas.

Además de comprobar señales de la interfaz, MCP envió clics reales a Reproducir/Pausar sobre el archivo largo: cursor 59 reproduciendo; después de pausar, cursor 193 y estable en dos consultas. Los controles eran visibles y habilitados según la inspección runtime.

### Comportamiento físico durante MERGE/SPLIT

- SOLID: personaje apoyado durante MERGE y SPLIT, sin pérdida de apoyo después de aterrizar.
- Naranja: apoyo durante MERGE/SPLIT; después del SPLIT atraviesa desde abajo, aterriza y desciende con abajo. No se encontró un collider sólido oculto sobre la región.
- Azul: conserva el rebote después de MERGE y SPLIT; también se verificó el impacto mientras la región se movía.
- Cero muestras con volúmenes regionales duplicados y cero incoherencias de material/propietario/ID en los commits observados.
- Un aumento de silueta ocupado se difirió conservando las formas anteriores; se aplicó al salir el personaje, sin teletransportarlo.
- Los MERGE/SPLIT ambiguos de seguimiento conservan la política previa: nuevas identidades cuando no existe evidencia suficiente; sus eventos de diagnóstico quedan en el archivo. Las pruebas Python previas de ambigüedad siguen pasando.

En la pasada headless final hubo 584 muestras activas de jugador, 3 rebotes, 2 descensos y 2 recuperaciones, cero penetraciones sólidas mayores a 1 px y cero pérdidas de apoyo durante movimiento. En MCP hubo 808 muestras y las mismas respuestas físicas. Los contactos contados incluyen el suelo auxiliar; atravesar intencionalmente el volumen naranja no se cuenta como penetración sólida.

Apoyo continuo observado tras aterrizar: 52 ticks en MERGE, 63 en SPLIT, 43 en ONE_WAY móvil y 22 en MERGE/SPLIT naranja, sin pérdidas. MCP registró 51 ticks en el primer caso por la fase de inicio; las otras mediciones coincidieron. Máximo paso mientras seguía apoyado: 0 px en las topologías inmóviles y **0,5221 px** en naranja móvil. El máximo de 5,2362 px incluyendo la caída inicial corresponde al aterrizaje de preparación, no a un salto de la plataforma.

En la batería completa se recibieron 2981 estados: 2973 aceptados/aplicados y 8 rechazados intencionalmente; un lote se difirió por ocupación. Hubo 228 reconstrucciones regionales, incluyendo reinicios, topologías y cambios de silueta. Los eventos lógicos totalizaron 44 MERGE y 38 SPLIT. El contador antiguo de topología física no los sustituye: las regiones persistentes pueden cambiar de propietario sin desaparecer.

El escenario largo aplicó los **1800 estados**, con 30 MERGE/29 SPLIT y ningún rechazo. Se verificó ausencia de colisiones duplicadas durante cada paso muestreado. Esto no equivale a probar una sesión humana de duración indefinida.

### Escenarios exportados

| Escenario | Estados | Aplicados | Rechazos esperados | MERGE/SPLIT | Resultado |
|---|---:|---:|---:|---:|---|
| 01_solid | 12 | 12 | 0 | 0/0 | FUNCIONA |
| 02_bounce | 12 | 12 | 0 | 0/0 | FUNCIONA |
| 03_one_way | 12 | 12 | 0 | 0/0 | FUNCIONA |
| 04_green_orange | 12 | 12 | 0 | 0/0 | FUNCIONA |
| 05_green_blue | 12 | 12 | 0 | 0/0 | FUNCIONA |
| 06_blue_orange | 12 | 12 | 0 | 0/0 | FUNCIONA |
| 07_three | 12 | 12 | 0 | 0/0 | FUNCIONA |
| 08_merge | 24 | 24 | 0 | 1/0 | FUNCIONA |
| 09_split | 36 | 36 | 0 | 1/1 | FUNCIONA |
| 10_cycles | 96 | 96 | 0 | 4/3 | FUNCIONA |
| 11_hole | 12 | 12 | 0 | 0/0 | FUNCIONA |
| 12_corner | 12 | 12 | 0 | 0/0 | FUNCIONA |
| 13_movement | 42 | 42 | 0 | 0/0 | FUNCIONA |
| 14_rotation | 57 | 57 | 0 | 0/0 | FUNCIONA |
| 15_silhouette | 24 | 24 | 0 | 0/0 | FUNCIONA |
| 16_material | 24 | 24 | 0 | 0/0 | FUNCIONA |
| 17_removal | 24 | 24 | 0 | 0/0 | FUNCIONA |
| 18_reappearance | 36 | 36 | 0 | 0/0 | FUNCIONA |
| 19_supported_merge | 65 | 65 | 0 | 1/0 | FUNCIONA |
| 20_supported_split | 77 | 77 | 0 | 1/1 | FUNCIONA |
| 21_mobile_one_way | 57 | 57 | 0 | 0/0 | FUNCIONA |
| 22_mobile_bounce | 57 | 57 | 0 | 0/0 | FUNCIONA |
| 23_duplicate | 13 | 12 | 1 | 0/0 | FUNCIONA |
| 24_old | 13 | 12 | 1 | 0/0 | FUNCIONA |
| 25_invalid | 12 | 11 | 1 | 0/0 | FUNCIONA |
| 26_long | 1800 | 1800 | 0 | 30/29 | FUNCIONA |
| 27_orange_merge_split | 36 | 36 | 0 | 1/1 | FUNCIONA |

### Tiempos medidos

Milisegundos en este equipo, bajo la carga de las suites. Validación incluye la validación lógica y preparación completa del estado; aplicación mide el commit físico y no todo el frame del juego. Percentiles empíricos sobre las muestras guardadas.

| Pasada · etapa | Muestras | Media ms | P50 ms | P95 ms | P99 ms | Máximo ms |
|---|---:|---:|---:|---:|---:|---:|
| headless · validation | 2981 | 6.264 | 5.235 | 13.214 | 22.956 | 59.888 |
| headless · application | 2973 | 0.505 | 0.295 | 1.654 | 4.633 | 19.246 |
| mcp · validation | 2981 | 4.001 | 3.943 | 6.590 | 7.973 | 15.302 |
| mcp · application | 2973 | 0.326 | 0.237 | 0.492 | 2.541 | 15.663 |

La validación tuvo picos cercanos a 60 ms en headless. Por lo tanto **no se afirma 60 FPS sostenidos** ni rendimiento de hardware físico: son pruebas sintéticas de transporte offline y física real de Godot. Antes de una entrada continua a 30 Hz conviene presupuestar y perfilar la preparación de snapshots completos.

## Regresiones ejecutadas

| Suite | Resultado |
|---|---:|
| Python: visión sintética, seguimiento, MERGE/SPLIT, contrato, offline, UDP y exportador nuevo | 152/152 |
| Fase 3B.2 física de materiales | 142/142 |
| Combate simultáneo en el laboratorio sobre geometría exportada: apoyo, intercambio y daño único | 3/3; 6 % cada jugador |
| Fase 1A | 92/92 |
| Fase 1C | 110/110 |
| Fase 1D, reproductor anterior | 127/127 |
| Fase 2A | 93/93 |
| Selección headless | 92/92 |
| Juego original gráfico, menús, movimiento, combate, vidas, victoria y reinicio | 235/235 |
| Selección gráfica | 111/111 |
| UDP anterior, integración gráfica | 37/37 |
| Protocolo UDP nuevo aislado | 160/160 |
| Contrato multimaterial Godot | 160/160 |
| Carga, parsing, instanciación e inicio físico Godot | 114 recursos sin fallos |

No se abrió hardware de captura: las pruebas de captura previas usan factories falsas inyectadas. Las suites del protocolo nuevo se ejecutan aisladas; no conectan esas entradas a estas físicas.

El primer intento de carga v2 descubrió una comparación por pertenencia a lista que distinguía números JSON decimales de enteros. Se corrigió la comparación de versión y se repitieron las suites v1/v2. Dos arranques headless de regresión sin ruta explícita de log terminaron con una traza nativa antes de mostrar el inicio del motor. Con `--log-file` dentro del proyecto ambas suites pasaron 160/160. No se alteraron sus pruebas para forzar un resultado positivo; las trazas se conservaron. La relación con permisos/log inicial es una hipótesis operativa, no una causa nativa demostrada. La importación headless del editor también encontró restricciones de AppData; se canceló y se utilizó el escaneo del editor MCP y la carga headless normal.

## Límites y preparación para 3C

- Se heredan los límites de 3B.2: ONE_WAY sólo habilita caras superiores hasta 46°, preflight con el rectángulo Player actual y StaticBody2D con pasos acotados. Rotaciones ocupadas o geometrías extremas pueden detenerse/diferirse conservadoramente.
- Un lote diferido puede bloquear el avance hasta que el personaje abandone el conflicto. No existe una política de descartar esa topología por un timeout, ni se fuerza penetración para continuar.
- Los archivos están acotados a 32 MiB y 10000 estados. No es un lector de streaming ilimitado.
- Los eventos regionales de ambigüedad están archivados; el panel resume MERGE/SPLIT y rechazos. No se inventan identidades para unir fragmentos ambiguos.
- No se verificó cámara, pared, proyector ni rendimiento de captura. Falta juego humano de dos personas durante cambios rápidos de topología y evaluación de sensación del rebote.
- No se reemplazaron plataformas originales ni se activó la regla futura de piso de seguridad por ausencia de estructuras.
- Antes de Fase 3C: ampliar estrés con más regiones y geometría móvil ocupada, perfilar los picos de validación y acordar la política de conflictos persistentes. Después conectar el receptor aislado al mismo adaptador, conservando sesiones, estados completos, materiales y límites. No construir otro backend físico.

La entrega se detiene aquí. **No se inició Fase 3C ni se conectó UDP con las físicas.**
