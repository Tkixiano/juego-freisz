# Independencia de colores — 2026-10-30

## Alcance y diagnóstico

Se inspeccionó y ejecutó el proyecto conectado mediante Godot AI MCP (Godot 4.6.3). Se revisaron máscaras, selección de contornos, observaciones, persistencia, JSON/UDP, receptor y PlatformManager. Se conservaron geometrías, dimensiones, gravedad, física y combate.

Cadena real: BGR → HSV → máscara independiente por color → apertura/cierre → candidatos → confirmación temporal y filtro → módulos JSON v1 → UDP loopback → validación/secuencia → mapeo fijo 1/left, 2/right → objetivos físicos suavizados. Posición: centroide del contorno, normalizado por ancho/alto menos uno. Orientación: eje mayor de minAreaRect, ambigua en piezas simétricas. Tres observaciones coherentes confirman una nueva adquisición; pérdidas breves conservan pose sin extrapolar y, al superar 150 ms, visible=false. Godot congela al perder seguimiento y nunca aplica posición de un módulo invisible. El timeout del receptor cubre el cierre/desconexión.

**Causas verificadas en código y reproducción:**

1. Antes, rangos HSV superpuestos permitían asignar el mismo contorno a ambos IDs. Se reprodujo con una imagen exclusivamente verde y ambos rangos iguales: ID1 e ID2 tenían el mismo centro. Ahora el conflicto de píxeles invalida conservadoramente ambos contornos. Los rangos guardados actualmente son disjuntos; esto no prueba que la superposición causara el incidente del usuario.
2. El seguimiento confiaba en la clave del diccionario y no comprobaba Observation.module_id. Ahora rechaza observaciones con identidad interna distinta y valores no finitos/fuera de rango. Es defensa adicional; el detector normal ya construía IDs fijos por color.
3. Los filtros anteriores medían área y llenado exterior del rectángulo, pero no la proporción de píxeles realmente compatibles dentro de la región. Podían aceptar regiones irregulares/huecas. La muestra real inicial, sin objeto verde distinguible, produjo 36 candidatos azules que superaron los criterios previos a confianza y fueron rechazados por la nueva pureza/cobertura. Esto identifica un mecanismo de falso positivo del entorno; no permite atribuir retrospectivamente cada movimiento observado a ese mecanismo.

No se encontró intercambio de IDs en el receptor: valida duplicados/desconocidos, orden de secuencia y mapeo fijo. Los ensayos integrados verificaron las aplicaciones por ID, no solo movimiento visual. La pérdida de seguimiento conserva identidad; nunca toma la pose del otro color.

## Correcciones

- Validación regional: área mínima y máxima por color, dimensión mínima, relación de aspecto, saturación, llenado y confianza (llenado × pureza). Apertura/cierre conservados.
- Rechazo completo de contornos que contienen píxeles compartidos entre máscaras; registro de conflicto.
- Dos candidatos comparables del mismo color se rechazan por ambigüedad. Los umbrales siguen configurables; esta política prefiere perder seguimiento a cambiar de pieza.
- Observaciones verificadas contra el ID del track; confirmación, puertas de movimiento, EMA y reacquisición existentes conservadas.
- Rechazo temprano de ruido por área evita calcular máscaras de región innecesarias.
- Diagnóstico de candidatos aceptados/rechazados, área, confianza, centro y estado; muestreo ROI HSV con aplicación explícita y guardado JSON independiente por color.
- Auditoría JSONL opcional desde candidatos hasta módulos enviados. Godot añade contador, última secuencia/ID/objetivo y traza acotada de transformaciones aplicadas. No se cambió el protocolo v1 ni los cinco campos del módulo.
- D oculta detalles Python, --no-gui evita ventanas; F3 oculta el diagnóstico Godot.

## Resultados ejecutados

| Prueba | Resultado |
|---|---|
| Python: suite existente + nuevos filtros/IDs | 40/40, segunda pasada conjunta aprobada |
| HighGUI real con imágenes sintéticas: ventanas, sliders, ROI, aplicar, guardar/cargar, selección, ocultar, salir | 10/10; se corrigió y repitió un redondeo circular de hue |
| UDP Godot: parsing, duplicados, desconocidos, paquetes fuera de orden/vencidos, pausas y modos | 37/37 |
| Regresión Godot: menús, controles, física, combate, vidas, victoria, reinicio | 225/225 |
| OpenCV sintético → tracking → socket UDP real → Godot | 9/9; verde solo, azul solo, ambos, verde móvil/azul fijo, pérdida y recuperación |
| Verde solo sintético, contador Godot | 58 aplicaciones left; 0 right; azul sin movimiento ni detección |
| Redragon real, solo verde preparado por el usuario, sin UDP | 107 fotogramas: 107 candidatos verdes aceptados, ningún candidato azul aceptado; seguimiento confirmó solo ID1 |
| Redragon real → UDP → Godot, solo verde | 106 fotogramas, 294 paquetes recibidos, 85 aplicaciones left, 0 right, azul sin cambio de transformación; inválidos=0, vencidos=0 |
| Redragon real → UDP → Godot, solo azul | 103 fotogramas, 291 paquetes recibidos, 62 aplicaciones right, 0 left, verde sin cambio de transformación; inválidos=0, vencidos=0 |
| Redragon real con ambos, movimiento y oclusión solicitados al usuario | 136 fotogramas, 352 paquetes; se confirmaron ambos IDs. Azul: LIVE → HOLD → LOST → LIVE. Verde: solo se confirmó cerca del final (3 muestras LIVE, 2 HOLD, 5 LOST); 126 muestras sin adquirir. Godot aplicó 2 objetivos a left y 123 a right. No se declara seguimiento simultáneo estable durante toda la prueba; requiere repetir encuadre y calibración conjunta. |
| Consola de Godot tras regresiones | Sin errores del juego en la ejecución inspeccionada |
| F3 vía entrada MCP | Ocultó el diagnóstico; modo MOUSE conservado |
| Carga/parsing headless | 43 recursos, sin fallos, en ejecución con acceso normal. El primer intento dentro del entorno restringido cerró con signal 11 antes de mostrar resultados; no se cuenta como aprobado. |

Los casos sintéticos cubren solo verde, solo azul, ambos, ninguno, ruido de ambos colores, brillo/saturación, reflejo blanco, oclusión, pérdida/reaparición, salto de posición, máscaras superpuestas, ID interno incorrecto, un fotograma falso y movimiento sin interferencia. Paquetes fuera de orden e ID desconocido se prueban en Godot.

**Métricas reales, muestra integrada verde:** captura ≈20.01 Hz a 640×480, último intervalo de procesamiento ≈20.13 FPS, OpenCV media 8.50 ms / P95 11.95 ms, envío medido 28.12 Hz. Promedio global de procesamiento 10.04 FPS incluyendo inicio/importación y espera de cámara. No se alcanzaron ni se afirman 30 FPS de cámara. Cierre normal sin reinicios ni terminación forzada. No se midieron FPS del render de Godot en esta etapa.

Evidencias: `artifacts/green_only_redragon_repeat.json[l]`, `artifacts/green_only_redragon_udp.json[l]`, `artifacts/blue_only_redragon_udp.json[l]`, `artifacts/both_redragon_udp.json[l]`, `artifacts/color_isolation_wire.json`, `artifacts/vision_gui_results.json`; Godot `validation/color_isolation_results.json`, `physical_green_isolation_results.json`, `physical_blue_isolation_results.json`, `physical_both_isolation_results.json`, `external_integration_results.json`. Se guardaron dos fotogramas locales para inspeccionar el encuadre; no se transmitieron imágenes por UDP.

## Uso de calibración

1. Desde la raíz: `python detector.py --no-udp` (Redragon configurada, DirectShow índice 2).
2. 1 verde / 2 azul. Arrastrar una región interior del objeto en la imagen principal. Consultar mediana, percentiles y rango sugerido en Calibration.
3. A aplica la sugerencia; ajustar H/S/V y filtros con los sliders. Revisar ambas máscaras y todos los rechazos. S guarda `vision/config.json`; L lo carga. Nunca se guarda o aplica una sugerencia automáticamente.
4. Q cierra. `python detector.py` o `RunDetector.cmd` inicia normalmente. En Godot F2 EXTERNAL; F3 diagnóstico opcional.
5. Para investigar un caso: `python detector.py --trace artifacts/detecciones.jsonl`. Un evento `observation` explica cada candidato; `udp_sent` identifica secuencia y módulos enviados; `module_last_update` de Godot identifica qué se aplicó.

## Pendientes y límites

- Se probaron físicamente verde solo y azul solo con aislamiento correcto. La prueba conjunta confirmó ambos y mostró pérdida/recuperación de azul, pero el verde no permaneció adquirido: repetir ambos enteros dentro de la imagen, movimiento/rotación y oclusión controlada. No hay video continuo que permita atribuir cada pérdida a oclusión, encuadre o umbral. Faltan variaciones deliberadas de iluminación. La mesa real fue probada; la pared definitiva requiere recalibrar.
- Una región del entorno del mismo color y con tamaño/forma compatibles puede seguir pasando todos los criterios. El color no identifica inequívocamente un objeto físico. No se promete eliminar toda falsa detección bajo cualquier iluminación.
- Rechazar conflictos o dos piezas comparables puede producir pérdida de seguimiento; es una decisión conservadora deliberada. El valor de confianza es geométrico/fotométrico, no una probabilidad.
- La pieza verde real de esta prueba dio confianza ≈0.60–0.63; no subir arbitrariamente ese umbral sin revisar la muestra. Los valores HSV conservados no se reemplazaron a partir de un solo fotograma.
- Una oclusión severa puede fragmentar la máscara y detener el seguimiento. Al reaparecer se confirma y suaviza; no se inventa movimiento.
- IDs semánticos dependen de calibración correcta: si se configura deliberadamente el rango azul como verde, el sistema rechaza superposición, pero no puede saber cuál era la intención del operador.
- La traza opcional crece con la duración; usarla en sesiones acotadas. Incluye configuración inicial y parámetros de color por observación para registrar la calibración en vivo; el envío identifica su fotograma fuente y también registra el cierre invisible. Las evidencias físicas anteriores al enriquecimiento final conservan secuencia, candidatos y módulos, pero no esos campos adicionales.
- No se implementaron proyector, homografía, reconstrucción de geometría ni cambios de combate.

## Archivos modificados/creados

Producción: `vision/config.py`, `vision/config.json`, `vision/detection.py`, `vision/tracking.py`, `vision/calibration.py` (nuevo), `vision/gui.py`, `vision/app.py`, `vision/README.md`; Godot `scripts/ExternalPlatformReceiver.gd`, `scripts/PlatformInputPanel.gd`.

Validación: `tests/test_color_isolation.py` (nuevo), `tests/gui_smoke.py`, `tests/send_color_isolation.py` (nuevo), Godot `validation/ColorIsolationValidation.gd` (nuevo), este informe y los reportes de ejecución indicados. Sin dependencias adicionales.
