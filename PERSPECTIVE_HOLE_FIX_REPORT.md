# Corrección del agujero bajo perspectiva

**Bloqueo resuelto.** La prueba `perspective_hole_accepted` pasa con la misma homografía y silueta. No se alteraron validadores, tolerancias, backend, UDP ni combate. Solo se cambió la preparación de geometría en Python.

## 1. Reproducción aislada

Caso de 3E.0: `CalibrationPreparationValidation.gd`, entrada `perspective_hole`, rechazo `part_fills_hole`. Responsable: `CompoundGeometryValidator.validate`, comprobación de intersección entre cada pieza convexa y los agujeros; el rechazo se propagaba por `MaterialGeometryValidator` antes de aplicar física.

Homografía de cámara: `[[2,0.03,0],[0.01,1.3,30],[0.0001,0.00005,1]]`. Se conserva la composición de medio píxel y el layout de 3E.0. La geometría original es una región verde con agujero y una extensión naranja; el contrato contiene exterior, agujero y particiones convexas.

Archivos completos: [reproduction.json](artifacts/perspective_hole/reproduction.json) contiene geometría original, H compuesta, contornos transformados, coordenadas mundiales finales, áreas firmadas y las intersecciones calculadas con Decimal de 80 dígitos. [minimal_pair.json](artifacts/perspective_hole/minimal_pair.json) contiene únicamente el cuadrilátero y el agujero que reproducen la intrusión. El log original de Godot está en `artifacts/perspective_hole/baseline.txt`.

## 2. Causa raíz demostrada

Intersección máxima del contrato float64 original: **5.74492070041e-12 px²** (error residual numérico). Tras convertir exactamente sus vértices a float32, un oráculo con Decimal80 mide **0.000410457172585 px²** de intrusión real. Godot devolvía **0,00199833605438 px²** para ese par. El límite existente es **0,0001 px²**.

El borde largo de una pieza pasaba por dos esquinas del agujero, pero no tenía vértices en esas uniones: una T-junction. La proyección es válida en float64; al redondear por separado el borde largo y las esquinas a Vector2/float32, dejan de ser collineales. Por tanto, no era correcto forzar la aceptación del contrato original: su partición se volvía inválida a la precisión del backend. El clipping amplificaba el área reconstruida, pero cambiarlo no eliminaba la intrusión real.

Se descartaron otras causas: todos los vértices se transformaban, el winding exterior era positivo y el de los agujeros negativo, los anillos eran simples y estaban separados, sin duplicados ni aristas degeneradas; el agujero estaba dentro del exterior y no había recorte de escenario. El rechazo aparecía durante validación de la descomposición, antes de construir colisiones.

Áreas firmadas originales: `[{"exterior": 32300.0, "holes": [-11200.0]}]`. Áreas firmadas proyectadas: `[{"exterior": 74246.57870490635, "holes": [-25789.26846208743]}]`. Coordenadas y orientación completas permanecen en el JSON para inspección.

## 3. Corrección mínima en generación

En `vision/calibrated_geometry.py`, únicamente para transformaciones oblicuas/proyectivas:

1. Se insertan los puntos de unión existentes en los bordes correspondientes, en coordenadas de origen. No se mueve ningún vértice del contorno ni se aproxima la silueta.

2. Solo las piezas convexas que reciben un vértice de borde se subdividen mediante un abanico con centro interior. Cada pieza resultante sigue siendo convexa y conserva exactamente el área de origen.

3. Se proyecta una tabla de vértices compartidos una sola vez y se reutilizan sus coordenadas en contornos, agujeros y piezas. Así, sus extremos siguen siendo idénticos tras convertir a float32.

4. La partición del padre se obtiene de las regiones de material, para que no haya dos descomposiciones incompatibles del mismo conjunto. Conserva propietarios, materiales, IDs, épocas, versiones y transacciones. Los casos afines alineados conservan la ruta anterior.

El caso pasó de **6 a 22 piezas** en el contrato. Son subdivisiones del mismo conjunto, no rectángulos sustitutos ni relleno de huecos. Las pruebas verifican área, no solapamiento, conservación de vértices originales y retroproyección.

Comprobación por SHA-256: los tres validadores originales permanecen idénticos: **True**. El mapper de referencia de benchmark reconstruye el código previo exacto, salvo rutas de importación del módulo de prueba: **True**.

## 4. Evidencia física

Suite específica: **70/70** headless y **70/70** mediante Godot AI MCP. Se realizaron **2398 consultas físicas dentro de los agujeros, con 0 impactos**. Además se comprobaron impactos positivos en el material sólido, para excluir un falso éxito por ausencia de cuerpos.

Máxima intersección geométrica pieza/agujero después: **0.0 px²**. El ensayo exige <=1e-8, más estricto que el umbral del backend. El contrato original sin corregir sigue siendo rechazado por el mismo validador.

Casos aprobados: original bajo perspectiva, agujero a una celda del exterior, exterior cóncavo, varios agujeros, rotación oblicua, giro de ejes de 90°, perspectiva fuerte válida, mezcla de SOLID/BOUNCE/ONE_WAY y agujero en BOUNCE. Las superficies superiores ONE_WAY mantienen su backend existente.

Casos inválidos rechazados: agujero rellenado por una pieza, agujero tocando o fuera del exterior, vértice duplicado, autointersección, pieza degenerada y recorte parcial/fuera de arena. Se compara la geometría comprometida byte a byte, transformaciones, revisiones y construcciones: no se aplica parcialmente ninguno de esos lotes. El mapper también conserva su ledger tras un recorte inválido.

## 5. Regresiones

La suite original de preparación pasó a **55/55**. Ahora se ejecutan comprobaciones que antes se omitían tras fallar la aceptación del agujero; no se retiró esa aserción.

Python: **198/198** (incluidas 11 regresiones específicas nuevas). Godot heredado: 2B 92/92; 2A 93/93; 1A 92/92; 1C 110/110; 1D 127/127; contrato multimaterial 160/160; física 3B.2 142/142; offline 3B.3 196/196; 3C 59/59; UDP 3A 160/160; integración 3D 43/43; carga y parsing aprobados. Logs y códigos de salida: `artifacts/perspective_hole/regressions/`.

Juego anterior por MCP: 235/235 generales, 111/111 selección y 37/37 UDP anterior. No se detectaron regresiones reproducibles.

Se actualizaron dos expectativas de prueba: la comparación geométrica dejó de exigir una correspondencia uno-a-uno de piezas, y verifica área/vértices/interiores; el antiguo rechazo seguro del agujero ahora verifica específicamente el rechazo de un cambio de calibración sin reset. Los controles de geometría inválida permanecen.

## 6. Rendimiento del caso

| Etapa | Antes P50/P95/P99 ms | Después P50/P95/P99 ms |
|---|---:|---:|
| Mapper Python, 100 muestras calientes | 4.395/6.269/8.269 | 8.965/12.455/13.302 |
| Validador Compound sin caché, 100 muestras | 1.712/2.684/3.374 | 7.947/11.020/11.414 |

La validación de antes terminaba en rechazo; la de después completa el examen de más piezas, por lo que no son cantidades de trabajo iguales. El coste adicional es real y se conserva en las muestras. No hay aplicación física válida anterior para comparar. No se hicieron optimizaciones generales ni se afirma una frecuencia de captura/render a partir de estos tiempos.

## 7. Archivos

Único archivo de producción modificado: `vision\calibrated_geometry.py`.

Pruebas existentes modificadas: `tests/test_calibrated_geometry.py`, `juegofrei/validation/CalibrationPreparationValidation.gd` y su fixture `calibration_preparation_cases.json`. Nuevos: `tests/perspective_hole_repro.py`, `perspective_mapper_reference.py` (solo referencia de pruebas), `perspective_hole_cases.py`, `test_perspective_hole.py`, `summarize_perspective_hole_fix.py`; `validation/PerspectiveHoleValidation.gd`, `PerspectiveHoleHeadless.gd`, `perspective_hole_cases.json`; este informe y evidencias bajo `artifacts/perspective_hole/`.

## 8. Reproducción

```powershell
python -m tests.perspective_hole_repro
python -m tests.perspective_hole_cases
python -m unittest tests.test_perspective_hole tests.test_calibrated_geometry
python tmp/run_perspective_hole_regressions.py
python -m tests.summarize_perspective_hole_fix
```
Suite aislada de Godot: `res://validation/PerspectiveHoleHeadless.gd`. La reproducción usa el mapper previo congelado; sigue mostrando el fallo original aunque la producción ya esté corregida.

## 9. Limitaciones y cierre

Se conservan los límites existentes (512 piezas por estructura en el mapper y presupuestos del transporte/backend). Una malla muy compleja puede superar el presupuesto tras subdividir: se rechaza de forma segura, no se simplifica ni se aumenta el límite. Uniones con coordenadas importadas no exactamente collineales pueden seguir siendo inválidas; no se ajustan con tolerancias arbitrarias.

Las limitaciones ópticas, feedback de color del proyector y transporte de personajes sobre geometría proyectiva cambiante de la auditoría 3E.0 no fueron objeto de esta corrección. No se utilizó cámara, VideoCapture ni proyector, no se modificó UDP o combate y no se avanzó de fase. El proyecto queda en OFFLINE.

Se marco el informe de auditoria 3E.0 como historico y se enlazo esta correccion; no se borraron sus resultados originales.
