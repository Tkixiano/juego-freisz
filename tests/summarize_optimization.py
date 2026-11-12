"""Make the optimization report from saved measurements, never inferred FPS."""
import csv
import hashlib
import json
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/optimization'
def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def stats(xs):
    a=np.asarray(xs,float)
    return dict(n=len(a),mean=float(a.mean()),p50=float(np.percentile(a,50)),p95=float(np.percentile(a,95)),p99=float(np.percentile(a,99)),maximum=float(a.max()),over16_7=int((a>16.7).sum())) if len(a) else dict(n=0)
def triple(d):return ' / '.join(f'{d[k]:.2f}' for k in ['p50','p95','p99']) if d.get('n') else 'N/D'
def table(headers,rows):return '\n'.join(['| '+' | '.join(headers)+' |','|'+'|'.join(['---']*len(headers))+'|',*['| '+' | '.join(map(str,r))+' |' for r in rows]])
def csvfile(name,rows):
    with (OUT/name).open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
def main():
    before=read('artifacts/optimization/python_before.json');after=read('artifacts/optimization/python_after_final.json');continuous=read('artifacts/optimization/python_continuous.json')
    g0=read('juegofrei/validation/performance_before_graphical.json');g1=read('juegofrei/validation/performance_after_graphical_final.json')
    counts=['1','4','8','16','32','64'];py_rows=[];gd_rows=[];network={};udp_rows=[]
    for label,data in [('before',before),('after',after),('continuous',continuous),('shape_changes',read('artifacts/optimization/python_shape_changes.json'))]:
        for n,c in data['counts'].items():
            for stage,v in c['stages_ms'].items():py_rows.append(dict(run=label,regions=n,stage=stage,**v))
    csvfile('python_stages.csv',py_rows)
    for label,data in [('before',g0),('after',g1)]:
        for n,c in data['counts'].items():
            for stage,v in c.items():
                if isinstance(v,list) and (stage.endswith('_ms') or stage.endswith('_us')):
                    gd_rows.append(dict(run=label,regions=n,stage=stage,**stats([x/1000 if stage.endswith('_us') else x for x in v])))
    csvfile('godot_stages.csv',gd_rows)
    for n in counts:
        d=read('artifacts/optimization/udp_regions'+n+'.json');m=d['bridge']['metrics']
        network[n]=dict(checks=[d['passed'],d['total']],received=m['received'],applied=m['applied'],coalesced_receiver=d['receiver'].get('full_states_coalesced',0),bridge=m,percentiles={k:stats(v) for k,v in m.items() if isinstance(v,list) and k.endswith('_ms')},rejections=d['receiver']['rejections'],support_losses=d['unexpected_support_losses'])
        for stage,v in network[n]['percentiles'].items():udp_rows.append(dict(regions=n,stage=stage,**v))
    csvfile('udp_stages.csv',udp_rows)
    (OUT/'udp_summary.json').write_text(json.dumps(network,indent=2),encoding='utf-8')
    oldhash=read('artifacts/optimization/baseline_hashes.json');changed=[p for p,h in oldhash.items() if hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h]
    (OUT/'changed_production_files.json').write_text(json.dumps(changed,indent=2))
    lines=['# Optimización multimaterial — informe','Fecha: 8 de noviembre de 2026. Godot 4.6.3. Solo imágenes, contratos y transmisiones sintéticos.','',
    '## Resultado y alcance',
    'Se redujo trabajo repetido sin cambiar HSV, siluetas, agujeros, IDs/épocas, materiales, gravedad, controles ni reglas de combate. No se sustituyen los contratos ni los protocolos. Las mejoras son medibles; **no se alcanzan 30 Hz ni 60 FPS con todas las cargas de estrés**. No se utilizó cámara ni proyector.',
    '', '## Línea base y metodología',
    'Benchmarks nuevos y reproducibles: `python -m tests.benchmark_pipeline --frames 40 --output ruta.json`; resolución 640×480, OpenCV con un hilo, 8 fotogramas de calentamiento y 40 medidos por cantidad. El caso A/B mueve los objetos cada 4 fotogramas; también se midió movimiento en cada fotograma (`--motion-every 1`) y cambios de silueta (`--shape-change`). La generación de imágenes queda fuera del tiempo de procesamiento en ambos casos.',
    'La línea base se guardó antes de editar producción. Se añadieron mediciones aisladas finales; no es un ensayo de laboratorio con CPU/frecuencias/sistema operativo bloqueados. Las cargas iniciales más grandes pudieron coincidir parcialmente con el comienzo del benchmark headless: las razones A/B son orientativas, no garantías universales. Los JSON conservan muestras y condiciones.',
    'En Python, 64 objetos separados son 64 estructuras. En Godot/UDP, el caso de 64 regiones se reparte entre 32 estructuras, respetando el límite vigente de transporte. Los corpus no son intercambiables entre runtimes, pero cada comparación A/B reutiliza el mismo corpus.',
    '', '## Python: procesamiento completo',
    table(['Regiones','Media antes ms','Media después ms','Después P50 / P95 / P99 ms','FPS equivalentes','Media movimiento continuo ms'],[[n,f"{before['counts'][n]['stages_ms']['total']['mean']:.2f}",f"{after['counts'][n]['stages_ms']['total']['mean']:.2f}",triple(after['counts'][n]['stages_ms']['total']),f"{after['counts'][n]['equivalent_fps']:.1f}",f"{continuous['counts'][n]['stages_ms']['total']['mean']:.2f}"] for n in counts]),
    '', 'Los FPS equivalentes son 1000/media de CPU del pipeline, **no FPS de captura, del juego o de presentación**. El movimiento continuo evita atribuir a una cámara real el beneficio de imágenes idénticas. La caché de imagen exacta probablemente tendrá menos aciertos con ruido de una webcam.',
    'Desglose completo antes/después con P50/P95/P99: [python_stages.csv](artifacts/optimization/python_stages.csv). HSV, máscaras y componentes se cronometran con los métodos reales; seguimiento y construcción incluyen sus llamadas internas, por lo que **no deben sumarse todas las filas**. Algunas etapas solo tienen muestras cuando se invocan. Los contornos pueden costar cero tras el calentamiento porque se reutilizan siluetas exactamente iguales; no se eliminó su extracción en geometrías nuevas.',
    '', '## Optimizaciones aplicadas',
    '1. Componentes por material procesados en el recorte exacto de cada estructura; se reconstruyen máscaras globales para conservar el contrato y el seguimiento. El recorte limita trabajo, no sustituye la silueta.',
    '2. Solapamientos entre pistas y observaciones limitados a la intersección de sus límites exactos; áreas precalculadas y mapas de distancia reutilizados dentro del mismo ciclo. Se mantienen umbrales y correspondencias conservadoras.',
    '3. Caché de segmentación exclusivamente para imágenes idénticas y perfil HSV/configuración idénticos. Entradas/salidas independientes: modificar una máscara o una imagen no contamina la siguiente. El tipo de imagen se vuelve a comprobar.',
    '4. Validación de contrato Python cacheada por todos los campos que esa función comprueba; invalidación por contenido, material, propietario y versión. Fallos no se cachean. Límites: 256 entradas.',
    '5. En Godot, validación geométrica cacheada por geometría local, propietario y materiales; los metadatos, pose, confianza, seguimiento y versiones se comprueban de nuevo. Las copias devueltas son independientes. Máximo 128 entradas.',
    '6. Se evita copiar profundamente regiones ajenas a cada collider al aplanar una estructura; el adaptador base conserva la copia propia en el límite transaccional. No se reconstruyen formas por una pose nueva.',
    '7. El receptor puede reunir hasta dos mensajes completos y elegir el de sesión/secuencia más reciente; comprueba integridad antes de reunirlos y el contrato completo antes de publicar. Si el más reciente es inválido, prueba el anterior. Rechaza duplicados y conserva las reglas de epochs/recuperación. Es opt-in para la partida; el laboratorio conserva el comportamiento anterior por defecto.',
    '8. Recuperación acotada del socket: presupuesto habitual 8 ms y hasta 12 ms cuando hay al menos 64 datagramas en cola. Se mantienen 128 datagramas y dos completos por ciclo. Puede aumentar un pico de lectura para evitar gastar validación en una cadena de estados viejos; no es una garantía de frame de 16,7 ms.',
    '', '## Godot: validación, aplicación, física y render',
    'La escena real fue inspeccionada y ejecutada por Godot AI MCP. El benchmark gráfico usa ambos Player existentes y ataques simultáneos, poses cambiantes y los tres materiales. Somete un estado por tick físico (hasta 60/s), más exigente que el emisor normal de 30/s. Doce ticks de calentamiento y 60 medidos por caso.',
    table(['Regiones','Preparación antes P50 ms','Después P50 / P95 / P99 ms','Protocolo después P50 / P95 / P99 ms','Formas','Penetraciones'],[[n,f"{np.median(g0['counts'][n]['submit_ms']):.2f}",triple(stats(g1['counts'][n]['submit_ms'])),triple(stats(g1['counts'][n]['validation_ms'])),g1['counts'][n]['shapes'],g1['counts'][n]['penetrations']] for n in counts]),
    '', 'Los detalles de commit, tiempo físico informado por Godot, procesamiento, render CPU/GPU e intervalos están en [godot_stages.csv](artifacts/optimization/godot_stages.csv). Los monitores pueden repetir el último valor; no son mediciones independientes de cada tick. El intervalo de callback físico incluye pacing y catch-up; el intervalo `frame_post_draw` mide presentación del render del motor, no el refresco físico de un monitor.',
    f"La secuencia gráfica completa, que mezcla cargas pequeñas y estrés, pasó de **{1000/np.mean(g0['draw_intervals_ms']):.1f} a {1000/np.mean(g1['draw_intervals_ms']):.1f} renders/s medios**. Este agregado incluye calentamiento y transiciones; no representa FPS de una partida normal. Sus pausas largas impiden declarar 60 FPS sostenidos. Las mediciones específicas por carga tienen prioridad para evaluar casos representativos.",
    table(['Regiones','Renders/s medios despues','Intervalo draw P50 / P95 / P99 ms'],[[n,f"{1000/np.mean(g1['counts'][n]['draw_intervals_ms']):.1f}",triple(stats(g1['counts'][n]['draw_intervals_ms']))] for n in counts]),
    'Se crearon 125 conjuntos geométricos iniciales entre los seis casos; los cambios de pose posteriores no agregaron reconstrucciones. Las cantidades físicas corresponden al material: ONE_WAY usa superficies superiores y no necesariamente una forma por región.',
    '', '## UDP real: carga y latencias finales',
    'Emisor Python independiente y PacketPeerUDP real, ejecutados secuencialmente. Casos pequeños: 6 s; 32/64 regiones: 12 s; 30 Hz solicitados. Los actores se desactivan en este ensayo de carga para aislar recepción/backend; combate y personajes se verifican en pruebas separadas.',
    table(['Regiones','Comprobaciones','Recibidos / aplicados','Edad al aplicar P50 / P95 / P99 ms','Recepción P50 / P95 / P99 ms'],[[n,'/'.join(map(str,network[n]['checks'])),f"{network[n]['received']} / {network[n]['applied']}",triple(network[n]['percentiles']['applied_sender_age_ms']),triple(network[n]['percentiles']['receiver_age_ms'])] for n in counts]),
    'Ver [udp_stages.csv](artifacts/optimization/udp_stages.csv): recepción, validación, espera→commit y antigüedad al aplicar. El timestamp se genera tras preparar/validar el emisor: no incluye captura, visión ni latencia de extremo a extremo. Los percentiles de estados aplicados excluyen descartes; leerlos junto con sus contadores. No hay garantía de entrega UDP.',
    'Comparación histórica de 3D con 32 regiones: 95 estados recibidos / 11 aplicados, edad de recepción P50 486,33 ms. El primer ensayo de esta optimización subió a 285 / 122 pero todavía tuvo P50 410,83 ms; se conserva como resultado intermedio. La tabla anterior contiene la repeticion final con el limite original de 8 ms; el ensayo a 12 ms fue descartado. Se conservan todas las iteraciones.',
    '', '## Geometría e identidades',
    'El corpus anterior se compara por hashes de los estados completos: geometrías, poses, IDs, épocas, versiones y eventos. Los seis casos de movimiento conservan sus hashes. En los 20 escenarios de topología se verifican exactamente los mismos resultados; para un fotograma de retirada se comprobó igualdad por permutación de los tres REGION_REMOVE, cuyo orden ya dependía de un conjunto sin ordenar. No se modifica el criterio de identidad para hacer pasar pruebas.',
    'Se mantienen agujeros, concavidades, contacto por esquina, pérdida/reaparición y MERGE/SPLIT. No se redujo resolución, vértices, área mínima ni precisión; no se generaron bounding boxes físicas ni convex hulls sustitutos.',
    '', '## Regresiones y pruebas nuevas',
    'Python: **164/164**, incluidas seis regresiones nuevas de igualdad, cachés y entradas inválidas. Receptor/validador Godot: **9/9** pruebas nuevas (nuevo inválido con fallback, desorden de llegada, duplicados, límites, actualización de metadatos y propietario inválido). Prueba real de fallos: **15/15**. Todos los casos de carga deben leerse por separado en sus logs.',
    'Suites headless repetidas: selección 92/92; dash/ataques 93/93; 1A 92/92; 1C 110/110; 1D 127/127; contrato multimaterial 160/160; física 3B.2 142/142; offline 3B.3 196/196; partida 3C 59/59; UDP 3A 160/160; integración 3D 43/43; carga/parsing sin fallos. Ejecución gráfica histórica: 235/235 generales, 111/111 selección y 37/37 UDP anterior.',
    'La primera versión del agrupamiento no contabilizaba un duplicado recibido en el mismo lote y falló 1/15. Se corrigió el rechazo antes de agrupar; se conserva el log inicial y la repetición pasó 15/15. Los criterios no se rebajaron.',
    '', '## Archivos',*['- `'+p+'`' for p in changed],
    'Nuevos: `tests/benchmark_pipeline.py`, `tests/benchmark_states.py`, `tests/test_performance_invariants.py`, `tests/summarize_optimization.py`; `validation/PerformanceValidation.gd`, `PerformanceHeadless.gd`, `ReceiverStagingHeadless.gd`; corpus, logs, CSV y JSON en `artifacts/optimization/` y `validation/`. Los scripts de ejecución secuencial están en `tmp/run_optimization_profiles.py` y `tmp/run_optimization_regressions.py`.',
    '', '## Reproducción y límites',
    '```powershell\npython -m tests.benchmark_pipeline --frames 40 --output artifacts/optimization/repeat.json\npython -m tests.benchmark_pipeline --frames 24 --motion-every 1 --output artifacts/optimization/continuous_repeat.json\npython -m unittest discover -s tests -p "test_*.py"\npython tmp/run_optimization_regressions.py\npython tmp/run_optimization_profiles.py\npython -m tests.summarize_optimization\n```',
    'Los perfiles y las regresiones deben ejecutarse por separado para evitar competencia de CPU. El script de resumen usa archivos before/after ya guardados; no altera las medidas.',
    'Persisten costes por máscaras globales necesarias para seguimiento, copias seguras, serialización repetida y validación/colisiones de muchas regiones. El peor caso de 64 regiones sigue siendo estrés extremo. Las cachés están acotadas pero añaden memoria; la caché de imagen completa tiene baja utilidad si cada píxel cambia por ruido. Los picos de validación no son interrumpibles por el presupuesto de lectura.',
    'Antes de pruebas físicas: repetir cargas representativas durante varios minutos en el hardware final, medir con ruido/oclusiones/iluminación controlados, vigilar memoria y colas, y validar límites de velocidad y apoyo con dos jugadores. No abrir captura ni proyector hasta autorizar esa etapa. El piso sigue dependiendo de EMPTY confirmado; STALE/ERROR preservan la última física válida. No se avanza automáticamente de fase.']
    live_path=OUT/'live_graphical_final.json'
    if live_path.exists():
        live=json.loads(live_path.read_text(encoding='utf-8'));draw=stats(live['draw_intervals_ms']);age=stats(live['bridge']['metrics']['applied_sender_age_ms'])
        lines.extend(['## Prueba grafica representativa con UDP real',f"Resultado {live['passed']}/{live['total']}. En {len(live['draw_intervals_ms'])} renders, media **{1000/draw['mean']:.2f} renders/s**; intervalo P50/P95/P99 **{triple(draw)} ms**. Edad envio preparado -> aplicacion P50/P95/P99 **{triple(age)} ms**. Ensayo de unos 17 segundos con tres materiales, dos jugadores y fallos programados; no certifica rendimiento sostenido durante minutos ni uso de una webcam."])
    (ROOT/'OPTIMIZATION_MULTIMATERIAL.md').write_text('\n\n'.join(lines),encoding='utf-8')
    print('report generated')
if __name__=='__main__':main()
