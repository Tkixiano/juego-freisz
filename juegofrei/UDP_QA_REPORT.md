# Integración UDP simulada — pruebas y entrega

Fecha: 30 de octubre de 2026. Sesión Godot AI MCP `juegofrei@fbd1`. Motor confirmado por MCP y ejecutable: Godot 4.6.3 estable oficial, Windows.

## Resultado

Implementada entrada UDP local JSON UTF-8 sobre las plataformas preexistentes, con modos excluyentes MOUSE/EXTERNAL. El proyecto conserva combate, gravedad, formas, dimensiones y colisiones. No se incorporaron OpenCV ni acceso a webcam.

La pasada final ejecutada dentro del juego mediante MCP aprobó **259/259 comprobaciones**: 34 específicas de UDP y 225 de regresión. Se realizó otra pasada UDP aprobada de 34/34 y una regresión anterior de 225/225. Además, el proceso headless de arranque/red aprobó 7/7 casos.

## Pruebas realmente ejecutadas

| Funcionalidad | Prueba | Resultado |
|---|---|---|
| Recepción | Datagramas reales de PacketPeerUDP a 127.0.0.1:5005 | FUNCIONA |
| Validación | 32 estructuras/tipos/rangos inválidos, bytes UTF-8 inválidos, sobrelongitud, IDs desconocidos/repetidos y escala | FUNCIONA; ignorados sin crear plataformas ni contaminar la secuencia |
| Secuencias | Antiguas, duplicadas y datagramas fuera de orden | FUNCIONA |
| Último estado | Varios paquetes por tick; máximo válido por secuencia; cola superior al presupuesto | FUNCIONA |
| Conversión | Coordenadas normalizadas a rectángulo (150,180,980,340), grados a radianes | FUNCIONA |
| Movimiento | Objetivos suavizados, sin teletransporte; traslación y rotación | FUNCIONA |
| Exclusión | Mouse, arrastre, Q/E y comandos de fuente incorrecta durante EXTERNAL | FUNCIONA; bloqueados |
| Modo | F2, clic real del botón del HUD, regreso a MOUSE y arrastre real posterior | FUNCIONA |
| Seguimiento | Omisión de un módulo mientras otro sigue activo; visible=false; recuperación con secuencia nueva | FUNCIONA |
| Comunicación | Fin de envío; watchdog; mantenimiento de pose y colliders | FUNCIONA |
| Pausa | Consumir UDP sin mover, descartar objetivos recibidos en pausa y exigir datos nuevos al reanudar | CORREGIDO Y VERIFICADO |
| Colisiones | Dos personajes sobre plataforma movida/rotada por UDP | FUNCIONA |
| Combate con UDP | Ataque fuerte mientras se mueve la plataforma: 14% de daño | FUNCIONA |
| Geometría | Comparación de escala, collider y polígonos antes/después | FUNCIONA; sin modificaciones |
| Red al arrancar | Inicio en EXTERNAL, puerto ocupado, aviso visible, reintento y liberación al salir | FUNCIONA; 7/7 |
| Regresión | Menús con clics, controles, pausa, reinicio, vidas, victoria, movimiento de P1/P2, combate, plataformas y caída controlada | FUNCIONA; 225/225 en ambas pasadas |

Los casos de combate incluyen daño único por activación, startup/recovery, hitstop, hitstun, dodge, ataques aéreos arriba/abajo, golpes simultáneos ligeros y fuertes con orden de procesamiento invertido, knockback en el borde, muerte durante hitstun y empate por doble eliminación. Los menús se probaron con eventos de mouse; la batería anterior también verifica señales y referencias.

## Python independiente

Se ejecutó `tools/simulate_platforms.py --duration 60` como proceso Python separado. El proceso terminó normalmente con **1798 paquetes enviados en 60.01 s**; Godot registró **1798 recibidos**, cero inválidos y cero secuencias rechazadas. Un muestreo durante el envío mostró 29.511 paquetes/s, dos módulos detectados, antigüedad local 35.026 ms y desplazamiento de la plataforma izquierda de 68.219 px respecto de la pose inicial. Los paquetes aplicados pueden ser menos que los recibidos porque sólo se usa el más reciente por ciclo.

El simulador envía left/right. top conserva la geometría y pose, y figura sin seguimiento. Después del cese de envío se comprobó estado SIN COMUNICACIÓN / SEGUIMIENTO PERDIDO y cero módulos detectados. Una captura MCP fresca, inspeccionada visualmente, mostró plataformas desplazadas/inclinadas, personajes y HUD. La captura guardada en `../artifacts/udp_simulation.png` corresponde al estado posterior al envío, con aviso de pérdida de seguimiento.

La primera ejecución Python dentro del aislamiento de Codex no alcanzó el loopback del proceso Godot. La repetición autorizada fuera del aislamiento confirmó el recorrido completo. No se modificaron firewall, permisos de Windows ni reglas de red del equipo.

## Problemas detectados y resueltos durante esta integración

1. Al pausar una plataforma en movimiento, AnimatableBody2D podía conservar un paso anterior y desplazarse aproximadamente 3 px al reanudar. `freeze_motion()` toma la pose autoritativa de PhysicsServer2D, cancela el movimiento pendiente y reinicia la interpolación. Las dos últimas pasadas UDP verificaron pose estable al reanudar sin datos nuevos.
2. El texto de arranque del simulador contenía una flecha Unicode que fallaba en una consola Windows con CP1252. Se reemplazó por texto ASCII y se volvió a ejecutar correctamente.

Una prueba inicial de arrastre también falló por faltar el evento de movimiento del cursor previo al clic. Se corrigió la simulación de entrada y se volvió a ejecutar con éxito; no se trataba de un error del controlador de mouse.

## Archivos de implementación modificados o creados

| Archivo | Cambio |
|---|---|
| scripts/ExternalPlatformReceiver.gd | Receptor independiente, validación, secuencias, watchdogs y diagnóstico. |
| scripts/PlatformManager.gd | Modos y validación de fuente; conserva registro/API existente. |
| scripts/MousePlatformController.gd | Exclusión en EXTERNAL, cancelación de arrastre y estado del editor. |
| scripts/DynamicPlatform.gd | Congelado/resincronización de la pose física; conserva suavizado y límites existentes. |
| scripts/PlatformInputPanel.gd | Botón de modo, F2 y diagnóstico a 10 Hz. |
| scenes/PlatformInputPanel.tscn | Panel de diagnóstico. |
| scenes/Main.tscn | Instancias del receptor y panel, referencias de scripts. |
| project.godot | Acción platform_control_mode ligada a F2. |
| tools/simulate_platforms.py | Emisor independiente a 30 Hz, argumentos y Ctrl+C. |
| tools/StartSimulation.cmd | Lanzador para Windows. |
| README.md, EXTERNAL_INPUT.md | Uso, formato, coordenadas, configuración y límites. |

No se modificaron PlayerController, PlayerMovement, CombatController, GameManager, recursos de ataque, Arena.tscn ni la geometría de DynamicPlatform.tscn en esta integración.

Pruebas nuevas: `validation/ExternalInputValidation.gd`, `ExternalIntegrationRegression.gd`, `ExternalStartupAudit.gd`, sus sidecars UID generados por Godot y los resultados JSON. Se reutilizaron las baterías existentes sin duplicar sus funcionalidades.

## Evidencia

- `validation/external_integration_results.json`: resumen final 34 + 225, cero fallos.
- `validation/udp_final.json`, `udp_pass4.json`: dos pasadas UDP aprobadas.
- `validation/full_udp_final.json`, `full_udp_regression.json`: regresiones completas.
- `validation/udp_startup.json`: puerto ocupado, reintento, cierre y modo inicial.
- `validation/python_stream_results.json`: muestreo en vivo y estado posterior al emisor Python.
- `validation/headless_qa.json`, `../artifacts/external_headless.log`: carga, parsing e instanciación.

Las primeras pasadas `udp_pass1/2/3.json` se conservan como historial de fallos y correcciones. No representan el estado final. Los logs MCP consultados del editor y juego no mostraron errores o advertencias del proyecto.

## Limitaciones pendientes

- Sin reconocimiento visual, webcam, calibración ni transporte de imágenes. La futura fuente debe respetar el protocolo y la convención de coordenadas documentados.
- Entrada restringida a loopback IPv4; sin autenticación ni sincronización de relojes. El HUD muestra antigüedad local, no latencia extremo a extremo.
- No se midieron 60 FPS estables en esta integración y no se exportó un ejecutable Windows.
- Queda pendiente una sesión presencial con dos jugadores para valorar sensación de control y balance bajo una futura fuente visual. Las pruebas automatizadas sí ejercitaron movimiento, colisiones y combate.

El juego quedó en modo MOUSE y los procesos simuladores terminaron.
