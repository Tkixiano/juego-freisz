> Actualizacion posterior: el bloqueo `perspective_hole_accepted` fue resuelto sin cambiar validadores. Ver [PERSPECTIVE_HOLE_FIX_REPORT.md](PERSPECTIVE_HOLE_FIX_REPORT.md). El contenido siguiente conserva el resultado historico de 3E.0.

# Auditoría de integración y calibración — preparación sintética

Fecha: 8 de noviembre de 2026. Godot 4.6.3. No se abrió cámara, VideoCapture ni salida de proyector.

## Resultado y bloqueo pendiente

**La preparación está implementada, pero la integración física completa todavía NO está lista para habilitarse sin restricciones.** El caso de perspectiva con agujero conserva un rechazo del backend (`part_fills_hole`). Se mantiene como prueba FALLIDA; no se cambiaron umbrales para convertirla en éxito. Se verifica aparte que el rechazo conserva la configuración física anterior. No hubo pruebas físicas.

Suite nueva Godot headless: **49/50**. MCP gráfico: **49/50**. Fallos headless: perspective_hole_accepted.

## 1. Arquitectura prevista y componentes reutilizados

Futuro capturador existente `CameraSource` → fotograma fresco + salud + metadatos reales de captura → `CalibratedMaterialSource` → `MaterialReplayExporter`/`MaterialStructures` existentes (HSV, seguimiento, MERGE/SPLIT, epochs) → `CalibratedGeometryMapper` → `Session`/fragmentación UDP 3A v2 → receptor 3D → gateway → adaptador transaccional → backend físico existente.

La cámara no está conectada a ese recorrido en esta fase. El límite nuevo acepta arrays y estados de salud, no abre dispositivos. Se reutilizan `ProjectionCalibration` (fit, carga, validación), marcadores ArUco y comprobaciones independientes, perfil HSV multimaterial, contratos geométricos y físicos existentes. No se crea un nuevo protocolo, controlador de combate ni sistema de colisiones.

## 2. Conexiones faltantes identificadas

- `vision.app` conserva el detector antiguo de módulos/centros y su transporte CAMERA/PROJECTOR. No debe usarse como si ya transmitiera siluetas multimaterial.

- Falta el ejecutable de captura real que entregue frames y metadatos al límite nuevo, seleccione explícitamente Redragon, conecte la salud de captura/calibración y rote sesiones al cambiar contexto. Se dejó deliberadamente sin implementar ni activar.

- El perfil HSV de tres materiales debe pasarse explícitamente al nuevo source (`config=load_materials(...)`); el perfil antiguo de dos módulos no se sobrescribe ni se convierte automáticamente.

- La homografía anterior solo mapeaba centros/ángulos. Ahora existe un adaptador para todas las regiones, agujeros y partes convexas. La transformación de una silueta no puede sustituirse por transformar solo su centro.

- El offset de laboratorio `(300,180)` no corresponde a geometría ya calibrada. El gateway lo omite exclusivamente con metadata espacial explícita y validada; las reproducciones anteriores conservan el offset.

- Pendientes críticos: precisión de intersecciones en perspectiva con agujeros, control de deriva de calibración durante uso, distorsión óptica y contaminación de color por la propia proyección.

## 3. Convención geométrica y recorrido

El contrato usa bordes de celdas a coordenadas enteras y centros en `n+0,5`. OpenCV calibra centros en enteros. Para cada vértice local se aplica pose global, se deshace el resize/recorte declarado, se resta 0,5, se aplica H y se vuelve a bordes de píxeles del lienzo proyectado sumando 0,5. Finalmente se escala y desplaza al rectángulo explícito del escenario.

`ImageLayout` declara resolución original, resolución procesada y crop. No se infiere un recorte a partir de la relación de aspecto. El lienzo proyectado lógico y Godot son 1280×720; los píxeles físicos HDMI pueden ser distintos. El mapper admite un rectángulo de arena explícito. Godot rechaza metadatos de resolución/rectángulo incompatibles.

Se transforman contornos exteriores, agujeros y cada parte convexa; no se rasteriza de nuevo, simplifica, redondea a enteros ni sustituye por hulls/rectángulos. La salida se expresa local a un ancla y con orientación 0: la rotación queda incorporada en los vértices. Esto conserva orientaciones y deformaciones proyectivas correctamente. Se corrige el winding si hay reflexión declarada.

Una homografía con perspectiva cambia la geometría local al mover una pieza: deben avanzar sus versiones, aunque la silueta de cámara no cambie. Una transformación afín mantiene geometría y versiones en cambios exclusivamente de pose. Se conservan IDs/epochs/eventos y el lote del mapper se publica solo si todas las regiones pasan.

Los vértices fuera del hull calibrado o del área permitida se rechazan: no se recortan silenciosamente. Se rechaza una segunda aplicación de la homografía. Cambiar firma/contexto espacial dentro de la misma fuente/sesión requiere reset/nueva sesión; no se reemplazan colisiones inmediatamente.

## 4. Calibración y persistencia

Se conserva el JSON de calibración existente, con matriz, captura/proyección, cámara/backend/mirror, correspondencias de ajuste y puntos independientes. La carga recalcula errores y valida degeneración, distribución, horizonte y orientación. Resolución, backend, índice o espejo incompatibles se rechazan. No se reemplazó ningún perfil existente.

`artifacts/preparation/SYNTHETIC_calibration.json` es exclusivamente de prueba y NO acredita una calibración real. No se encontró un perfil real `vision/projector_calibration.json` en esta inspección; sí existen artefactos sintéticos históricos. El hash `calibration_signature` identifica H, layout y arena: no es autenticación.

El antiguo patrón describe un área para centros. Para siluetas nuevas debe quedar dentro del área calibrada el contorno entero. El patrón y los textos heredados no implican que cualquier forma quepa con solo ubicar su centro.

## 5. Seguridad y estados

| Situación | Resultado preparado |
|---|---|
| Cámara desconectada/error declarado | ERROR; última geometría, sin EMPTY confirmado |
| Sin frame fresco | STALE; no paquete nuevo, timeout del receptor |
| Calibración ausente/incompatible/degenerada | Error de configuración; sin fallback a CAMERA |
| Array vacío, tipo o resolución incorrectos | ERROR, sin alimentar el tracker como imagen negra |
| Imagen válida sin módulos | Confirmación temporal del tracker + 3 observaciones vacías antes de EMPTY |
| Oclusión breve | Estado retenido; no falsa ausencia |
| Error de segmentación/mapeo | ERROR, lote descartado, última geometría válida |
| Emisor interrumpido | Timeout STALE, nunca EMPTY |
| Recuperación/nueva sesión | Estado completo validado; se conservan colliders hasta una transición segura |

STALE no se añadió como tipo de mensaje al wire existente. ERROR se publica explícitamente con `empty_confirmed=false`. El piso mantiene las reglas de 3C. El source no acumula una película de frames en memoria; reutiliza el exportador manteniendo solo su seguimiento/epochs.

## 6. Pruebas y errores medidos

Python: referencias y medio píxel; identidad, escalado, crop, aspecto, offset y rotación de ejes; transformación de pose en todos los vértices; tres materiales; concavidades/agujeros/contactos; perspectiva; winding reflejado; versiones; doble transformación; fuera de área; persistencia; cambios de resolución; calibración inválida; fallos/recuperación; configuración HSV inyectada y MERGE/SPLIT conservados.

Godot: colisiones calibradas sin offset duplicado, materiales, conteo y posiciones, agujeros afines, personaje aterrizando, fixture antiguo con offset, metadata ausente/incompatible, cambio de calibración, geometría fuera de arena, rechazo atómico, STALE/ERROR y contraejemplo de contención cóncava. Un proceso Python independiente envió imágenes sintéticas por UDP real: se aplicaron los tres materiales, hubo ERROR/STALE y reinicio de sesión, sin convertir el fallo de cámara simulado en EMPTY.

Error analítico máximo de puntos: **0 px**. Check independiente analítico máximo: **5.68434189e-14 px**. ArUco sobre imagen sintética deformada: RMS **0.7271 px**, máximo **0.9243 px**. Unidades: píxeles lógicos de proyección, no milímetros ni HDMI nativo.

Error máximo observado entre vértices float64 exportados y geometría mundial de Godot en los casos aceptados: **2.45553036e-05 px**. No es un ensayo de precisión física de cámara/proyector.

Correcciones verificadas: comparación de arrays JSON float/int en dimensiones; separación de offset de laboratorio; medio píxel; versiones por deformación proyectiva; retención ante fallos; inyección del perfil HSV existente. El chequeo de agujero escalado rechazaba por una diferencia de área reconstruida por clipping (~0,002136 px²). Se sustituyó por contención topológica y, cuando hay contención completa, se usa el área original en vez de vértices reconstruidos. No se ampliaron epsilons. Se prueban también cruces por vértices de una concavidad.

**FALLA pendiente:** `perspective_hole_accepted`. En ese caso la intersección pieza/agujero devuelve aproximadamente 0,001998 px², sobre el límite existente. La hipótesis es precisión float32/cuantización del kernel; no se da por completamente aislada. Se rechaza el lote sin rellenar el hueco ni destruir la última geometría. No se convirtió esta prueba roja en una expectativa de éxito para ocultarla.

## 7. Coste adicional y referencia 3D.1

Mapping + copias + validación de contratos y versiones, 80 muestras calientes por caso; sin segmentación, captura, UDP ni física:

| Regiones | P50 ms | P95 ms | P99 ms |
|---|---:|---:|---:|
| 1 | 2.974 | 4.441 | 4.712 |
| 4 | 12.806 | 16.823 | 17.752 |
| 8 | 14.450 | 24.752 | 26.041 |
| 16 | 28.252 | 40.593 | 47.954 |
| 32 | 57.416 | 80.857 | 86.415 |
| 64 | 57.942 | 65.130 | 70.901 |

Revalidación aislada del perfil al inicializar (no cada frame): P50/P95/P99 **3.042/3.549/3.569 ms**. Fit y validación tienen serie separada. Ver `artifacts/preparation/metrics.json`.

Los casos 32/64 usan hasta 32 estructuras y 64 regiones, como los fixtures de transporte. Es overhead de un adaptador de preparación, no FPS equivalentes del pipeline completo. Los resultados 3D.1 se conservan en `artifacts/optimization/` y `OPTIMIZATION_MULTIMATERIAL.md`; no se reemplazaron ni se afirma una comparación A/B entre corpus distintos. El coste adicional limita aún más los casos grandes. No se redujo precisión para acelerar.

## 8. Regresiones

Ver `artifacts/preparation/python_regressions_final.txt`, `profile_injection_tests.txt` y `regressions/`. Las suites heredadas de geometría, materiales, física, combate, selección y UDP se repitieron. La suite 3D tuvo un timeout de infraestructura al intentar escribir `udp_startup.json` (FileAccess nulo). Se añadieron reintentos acotados y salida de error explícita; la repetición pasó 43/43 sin modificar sus aserciones.

Los fallos de compatibilidad nuevos se informan separados de regresiones del juego anterior. No se modificaron controles, estadísticas, gravedad, formas de plataformas originales ni protocolos CAMERA/PROJECTOR. Los cambios de producción previos a esta tarea, detectados por hash, son:

- `vision\material_replay.py`

- `juegofrei\scripts\geometry\CompoundGeometryValidator.gd`

- `juegofrei\scripts\integrated\OfflineSceneGateway.gd`

Creados: `vision/calibrated_geometry.py`, `vision/calibrated_source.py`; pruebas `test_calibrated_geometry.py`, `calibration_preparation.py`, `send_calibrated_synthetic.py`, `summarize_preparation.py`; validaciones Godot `CalibrationPreparationValidation.gd`, `CalibrationPreparationHeadless.gd`, `CalibrationDiagnostic.gd`; fixtures, métricas y logs bajo `artifacts/preparation/` y `validation/`.

## 9. Riesgos antes de hardware

- Una homografía supone una pared plana; no corrige distorsión radial de lente ni espesor/paralaje de piezas.

- Mover cámara/proyector, cambiar zoom, enfoque, FOV, recorte de dispositivo o espejo puede invalidar H sin cambiar la resolución declarada. Los checks guardados no detectan deriva física actual. Falta supervisión de referencias sobre frames nuevos.

- Un índice de cámara puede identificar otro dispositivo después de reconectar. La futura aplicación debe verificar Redragon explícitamente y bloquear fallback a la integrada.

- La proyección de verdes/azules/naranjas del propio juego puede contaminar HSV y realimentar siluetas. Color solo no distingue luz proyectada de una pieza del mismo color; falta política de separación/ROI/tiempos de iluminación, a validar con hardware autorizado.

- ArUco puede fallar por exposición, enfoque, reflejos, oclusiones y geometría de montaje. No hay evidencia física aún.

- La calibración se refiere al lienzo lógico 1280×720. Deben mantenerse escalado/letterbox, pantalla y patrón idénticos entre calibración y juego. Recorte/resize software se declaran; transformaciones adicionales no declaradas no son seguras.

## 10. Procedimiento propuesto para la primera prueba física — NO ejecutado

1. Resolver o delimitar explícitamente el rechazo de perspectiva con agujeros y cerrar el ejecutable de captura real. Mantener OFFLINE/piso de seguridad y la física desconectada mientras se calibra.

2. Con autorización para hardware, verificar identidad de Redragon y seleccionar una resolución final fija. No permitir selección automática de la cámara integrada. Guardar copias separadas de perfiles; no promover el JSON sintético a perfil real.

3. Montar cámara/proyector rígidamente, fijar exposición/enfoque y pantalla de salida, comprobar relación de aspecto y el lienzo 1280×720. Usar el modo de calibración existente fuera del combate.

4. Capturar los ocho marcadores: cuatro FIT y cuatro CHECK independientes. Validar distribución, ejes y errores; confirmar manualmente el archivo candidato solo si cumple. Repetir tras cualquier movimiento.

5. Con la salida del juego todavía deshabilitada, calibrar HSV de los tres materiales sobre imágenes de esa iluminación, comprobar reflejos y contaminación por el proyector. Registrar frames para reproducción offline.

6. Reproducir esas imágenes sin cámara: verificar todos los contornos, huecos, límites y superposición contra la pared; probar fallos y recuperación. Una pieza cuyo contorno no quepa en el área calibrada debe rechazarse, no cortarse silenciosamente.

7. Solo después habilitar el nuevo driver hacia UDP, en una sesión nueva, empezando con una pieza convexa SOLID y sin jugadores. Luego BOUNCE/ONE_WAY, varios materiales y por último jugadores/MERGE/SPLIT. Mantener parada de fuente y último estado válido; no habilitar estructuras con agujeros en perspectiva hasta resolver el caso pendiente.

Comandos seguros que solo generan/prueban datos sintéticos:
```powershell
python -m tests.calibration_preparation --frames 80
python -m unittest tests.test_calibrated_geometry
python tmp/run_preparation_regressions.py
python -m tests.summarize_preparation
```
El test nativo nuevo sale con código de fallo mientras continúe `perspective_hole_accepted`. Los logs y el informe lo conservan explícitamente.

No se iniciaron pruebas físicas ni se avanzó de fase.

## Conteos finales y comprobaciones adicionales

**187/187 Python**; suite nueva **23/23**. Godot nuevo **49/50** headless y **49/50** por MCP: únicamente `perspective_hole_accepted` permanece FALLA. La perspectiva de una superficie sólida convexa sí pasó. La prueba separada de rechazo seguro del agujero también pasó.

Regresiones headless aprobadas: 2B 92/92, 2A 93/93, 1A 92/92, 1C 110/110, 1D 127/127, contrato 160/160, 3B.2 142/142, 3B.3 196/196, 3C 59/59 y 3A 160/160. Repetición 3D 43/43 después del fallo de escritura de reporte. Juego anterior por MCP: 235/235 generales, 111/111 selección y 37/37 UDP anterior.

Se reprodujo otro riesgo: rangos HSV superpuestos podían hacer que el tracker terminara reportando EMPTY pese a una región ambigua. El límite nuevo bloquea el snapshot completo como STALE si hay píxeles de clasificación conflictiva, conservando las estructuras anteriores. La prueba también verifica que el cambio de perfil invalida la caché. No se cambió el tracker ni los perfiles guardados.

Una imagen malformada o sin píxeles es ERROR; una imagen negra de tamaño válido sigue siendo una observación válida. Una cámara tapada, exposición incorrecta o un frame congelado con dimensiones correctas necesitan un supervisor de calidad/frescura en el futuro driver: el algoritmo no puede garantizar ausencia física a partir de esos píxeles solamente.

Los tiempos de mapping se midieron con una transformación afín. Bajo perspectiva, el movimiento también cambia la geometría y puede reconstruir formas; no se certificó el comportamiento de transporte del personaje sobre una silueta proyectiva deformándose. El backend anterior suaviza principalmente cambios exclusivamente de pose. Se requiere validar ese caso antes de permitir piezas móviles con jugadores encima.

La metadata espacial es una extensión optativa sobre el transporte v2. Un gateway anterior que la ignore sumaría el offset de laboratorio: no enviar tramas calibradas a builds anteriores. Falta negociación automática de capacidades; el futuro driver debe comprobar explícitamente la versión de gateway compatible.

El transporte es unidireccional. Falta trasladar al operador Python los rechazos del backend: ACTIVE del emisor no equivale a confirmación de aplicación física. El caso pendiente demuestra que un contrato válido en Python float64 puede ser rechazado en Godot.

También se modificó el harness `juegofrei/validation/UdpMatchHeadless.gd` para reintentar de forma acotada la escritura de su reporte y fallar explícitamente si no puede guardarlo. No se modificaron sus aserciones.

Al terminar se dejó abierta la escena principal en su modo OFFLINE predeterminado, sin emisor calibrado activo. No se conectó hardware ni se avanzó de fase.