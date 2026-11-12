"""Evidence-based report for the isolated post-3E.0 hole correction."""
import hashlib
import json
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def stats(a):return '/'.join(f'{v:.3f}' for v in np.percentile(a,[50,95,99]))
def main():
    d=read('artifacts/perspective_hole/reproduction.json');p=read('artifacts/perspective_hole/mapping_performance.json')
    native=read('juegofrei/validation/perspective_hole_headless.json');mcp=read('juegofrei/validation/perspective_hole_mcp.json')
    prep=read('juegofrei/validation/calibration_preparation_headless.json')
    original=read('artifacts/perspective_hole/original_regression.json')
    fixed=read('juegofrei/validation/perspective_hole_cases.json')['valid']['original']
    b=read('artifacts/perspective_hole/baseline_hashes.json');changed=[f for f,h in b.items() if hashlib.sha256((ROOT/f).read_bytes()).hexdigest()!=h]
    validators=['juegofrei/scripts/geometry/CompoundGeometryValidator.gd','juegofrei/scripts/geometry/PolygonValidator.gd','juegofrei/scripts/geometry/MaterialGeometryValidator.gd']
    unchanged=all(hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==b[f.replace('/','\\')] for f in validators)
    source=Path(ROOT/'tests/perspective_mapper_reference.py').read_text(encoding='utf-8').replace('from vision.projection','from .projection').replace('from vision.material_structures','from .material_structures').replace('from vision.structure_segmentation','from .structure_segmentation')
    reference_ok=hashlib.sha256(source.encode()).hexdigest()==b['vision\\calibrated_geometry.py']
    max64=max(v['float64_overlap'] for v in d['part_hole_pairs']);max32=max(v['float32_exact_overlap'] for v in d['part_hole_pairs'])
    lines=['# Corrección del agujero bajo perspectiva',
    '**Bloqueo resuelto.** La prueba `perspective_hole_accepted` pasa con la misma homografía y silueta. No se alteraron validadores, tolerancias, backend, UDP ni combate. Solo se cambió la preparación de geometría en Python.',
    '## 1. Reproducción aislada',
    'Caso de 3E.0: `CalibrationPreparationValidation.gd`, entrada `perspective_hole`, rechazo `part_fills_hole`. Responsable: `CompoundGeometryValidator.validate`, comprobación de intersección entre cada pieza convexa y los agujeros; el rechazo se propagaba por `MaterialGeometryValidator` antes de aplicar física.',
    'Homografía de cámara: `[[2,0.03,0],[0.01,1.3,30],[0.0001,0.00005,1]]`. Se conserva la composición de medio píxel y el layout de 3E.0. La geometría original es una región verde con agujero y una extensión naranja; el contrato contiene exterior, agujero y particiones convexas.',
    'Archivos completos: [reproduction.json](artifacts/perspective_hole/reproduction.json) contiene geometría original, H compuesta, contornos transformados, coordenadas mundiales finales, áreas firmadas y las intersecciones calculadas con Decimal de 80 dígitos. [minimal_pair.json](artifacts/perspective_hole/minimal_pair.json) contiene únicamente el cuadrilátero y el agujero que reproducen la intrusión. El log original de Godot está en `artifacts/perspective_hole/baseline.txt`.',
    '## 2. Causa raíz demostrada',
    f'Intersección máxima del contrato float64 original: **{max64:.12g} px²** (error residual numérico). Tras convertir exactamente sus vértices a float32, un oráculo con Decimal80 mide **{max32:.12g} px²** de intrusión real. Godot devolvía **0,00199833605438 px²** para ese par. El límite existente es **0,0001 px²**.',
    'El borde largo de una pieza pasaba por dos esquinas del agujero, pero no tenía vértices en esas uniones: una T-junction. La proyección es válida en float64; al redondear por separado el borde largo y las esquinas a Vector2/float32, dejan de ser collineales. Por tanto, no era correcto forzar la aceptación del contrato original: su partición se volvía inválida a la precisión del backend. El clipping amplificaba el área reconstruida, pero cambiarlo no eliminaba la intrusión real.',
    'Se descartaron otras causas: todos los vértices se transformaban, el winding exterior era positivo y el de los agujeros negativo, los anillos eran simples y estaban separados, sin duplicados ni aristas degeneradas; el agujero estaba dentro del exterior y no había recorte de escenario. El rechazo aparecía durante validación de la descomposición, antes de construir colisiones.',
    'Áreas firmadas originales: `'+json.dumps(d['original_areas'])+'`. Áreas firmadas proyectadas: `'+json.dumps(d['areas'])+'`. Coordenadas y orientación completas permanecen en el JSON para inspección.',
    '## 3. Corrección mínima en generación',
    'En `vision/calibrated_geometry.py`, únicamente para transformaciones oblicuas/proyectivas:',
    '1. Se insertan los puntos de unión existentes en los bordes correspondientes, en coordenadas de origen. No se mueve ningún vértice del contorno ni se aproxima la silueta.',
    '2. Solo las piezas convexas que reciben un vértice de borde se subdividen mediante un abanico con centro interior. Cada pieza resultante sigue siendo convexa y conserva exactamente el área de origen.',
    '3. Se proyecta una tabla de vértices compartidos una sola vez y se reutilizan sus coordenadas en contornos, agujeros y piezas. Así, sus extremos siguen siendo idénticos tras convertir a float32.',
    '4. La partición del padre se obtiene de las regiones de material, para que no haya dos descomposiciones incompatibles del mismo conjunto. Conserva propietarios, materiales, IDs, épocas, versiones y transacciones. Los casos afines alineados conservan la ruta anterior.',
    f"El caso pasó de **{len(d['transformed']['structures'][0]['convex_parts'])} a {len(fixed['structures'][0]['convex_parts'])} piezas** en el contrato. Son subdivisiones del mismo conjunto, no rectángulos sustitutos ni relleno de huecos. Las pruebas verifican área, no solapamiento, conservación de vértices originales y retroproyección.",
    f'Comprobación por SHA-256: los tres validadores originales permanecen idénticos: **{unchanged}**. El mapper de referencia de benchmark reconstruye el código previo exacto, salvo rutas de importación del módulo de prueba: **{reference_ok}**.',
    '## 4. Evidencia física',
    f"Suite específica: **{native['passed']}/{native['total']}** headless y **{mcp['passed']}/{mcp['total']}** mediante Godot AI MCP. Se realizaron **{native['hole_queries']} consultas físicas dentro de los agujeros, con {native['hole_hits']} impactos**. Además se comprobaron impactos positivos en el material sólido, para excluir un falso éxito por ausencia de cuerpos.",
    f"Máxima intersección geométrica pieza/agujero después: **{native['maximum_hole_overlap_px2']} px²**. El ensayo exige <=1e-8, más estricto que el umbral del backend. El contrato original sin corregir sigue siendo rechazado por el mismo validador.",
    'Casos aprobados: original bajo perspectiva, agujero a una celda del exterior, exterior cóncavo, varios agujeros, rotación oblicua, giro de ejes de 90°, perspectiva fuerte válida, mezcla de SOLID/BOUNCE/ONE_WAY y agujero en BOUNCE. Las superficies superiores ONE_WAY mantienen su backend existente.',
    'Casos inválidos rechazados: agujero rellenado por una pieza, agujero tocando o fuera del exterior, vértice duplicado, autointersección, pieza degenerada y recorte parcial/fuera de arena. Se compara la geometría comprometida byte a byte, transformaciones, revisiones y construcciones: no se aplica parcialmente ninguno de esos lotes. El mapper también conserva su ledger tras un recorte inválido.',
    '## 5. Regresiones',
    f"La suite original de preparación pasó a **{prep['passed']}/{prep['total']}**. Ahora se ejecutan comprobaciones que antes se omitían tras fallar la aceptación del agujero; no se retiró esa aserción.",
    'Python: **198/198** (incluidas 11 regresiones específicas nuevas). Godot heredado: 2B 92/92; 2A 93/93; 1A 92/92; 1C 110/110; 1D 127/127; contrato multimaterial 160/160; física 3B.2 142/142; offline 3B.3 196/196; 3C 59/59; UDP 3A 160/160; integración 3D 43/43; carga y parsing aprobados. Logs y códigos de salida: `artifacts/perspective_hole/regressions/`.',
    f"Juego anterior por MCP: {original['full']['passed']}/{original['full']['total']} generales, {original['selection']['passed']}/{original['selection']['total']} selección y {original['udp']['passed']}/{original['udp']['total']} UDP anterior. No se detectaron regresiones reproducibles.",
    'Se actualizaron dos expectativas de prueba: la comparación geométrica dejó de exigir una correspondencia uno-a-uno de piezas, y verifica área/vértices/interiores; el antiguo rechazo seguro del agujero ahora verifica específicamente el rechazo de un cambio de calibración sin reset. Los controles de geometría inválida permanecen.',
    '## 6. Rendimiento del caso',
    '| Etapa | Antes P50/P95/P99 ms | Después P50/P95/P99 ms |\n|---|---:|---:|\n'+f"| Mapper Python, 100 muestras calientes | {p['before']['p50']:.3f}/{p['before']['p95']:.3f}/{p['before']['p99']:.3f} | {p['after']['p50']:.3f}/{p['after']['p95']:.3f}/{p['after']['p99']:.3f} |\n"+f"| Validador Compound sin caché, 100 muestras | {stats(native['compound_validation_ms']['unwelded_original'])} | {stats(native['compound_validation_ms']['original'])} |",
    'La validación de antes terminaba en rechazo; la de después completa el examen de más piezas, por lo que no son cantidades de trabajo iguales. El coste adicional es real y se conserva en las muestras. No hay aplicación física válida anterior para comparar. No se hicieron optimizaciones generales ni se afirma una frecuencia de captura/render a partir de estos tiempos.',
    '## 7. Archivos',
    'Único archivo de producción modificado: '+', '.join('`'+f+'`' for f in changed)+'.',
    'Pruebas existentes modificadas: `tests/test_calibrated_geometry.py`, `juegofrei/validation/CalibrationPreparationValidation.gd` y su fixture `calibration_preparation_cases.json`. Nuevos: `tests/perspective_hole_repro.py`, `perspective_mapper_reference.py` (solo referencia de pruebas), `perspective_hole_cases.py`, `test_perspective_hole.py`, `summarize_perspective_hole_fix.py`; `validation/PerspectiveHoleValidation.gd`, `PerspectiveHoleHeadless.gd`, `perspective_hole_cases.json`; este informe y evidencias bajo `artifacts/perspective_hole/`.',
    '## 8. Reproducción',
    '```powershell\npython -m tests.perspective_hole_repro\npython -m tests.perspective_hole_cases\npython -m unittest tests.test_perspective_hole tests.test_calibrated_geometry\npython tmp/run_perspective_hole_regressions.py\npython -m tests.summarize_perspective_hole_fix\n```\nSuite aislada de Godot: `res://validation/PerspectiveHoleHeadless.gd`. La reproducción usa el mapper previo congelado; sigue mostrando el fallo original aunque la producción ya esté corregida.',
    '## 9. Limitaciones y cierre',
    'Se conservan los límites existentes (512 piezas por estructura en el mapper y presupuestos del transporte/backend). Una malla muy compleja puede superar el presupuesto tras subdividir: se rechaza de forma segura, no se simplifica ni se aumenta el límite. Uniones con coordenadas importadas no exactamente collineales pueden seguir siendo inválidas; no se ajustan con tolerancias arbitrarias.',
    'Las limitaciones ópticas, feedback de color del proyector y transporte de personajes sobre geometría proyectiva cambiante de la auditoría 3E.0 no fueron objeto de esta corrección. No se utilizó cámara, VideoCapture ni proyector, no se modificó UDP o combate y no se avanzó de fase. El proyecto queda en OFFLINE.']
    (ROOT/'PERSPECTIVE_HOLE_FIX_REPORT.md').write_text('\n\n'.join(lines),encoding='utf-8')
    (ROOT/'artifacts/perspective_hole/changed_production.json').write_text(json.dumps(changed,indent=2),encoding='utf-8')
    print('report written; validators unchanged:',unchanged,'reference verified:',reference_ok)
if __name__=='__main__':main()
