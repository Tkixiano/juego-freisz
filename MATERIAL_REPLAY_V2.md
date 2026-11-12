# Reproducción offline multimaterial v2

Transporte: **archivo JSON UTF-8 local**, sin sockets. No cambia ningún protocolo UDP. Geometría: contrato v1 y extensión multimaterial v1 de `MATERIAL_CONTRACT_V1.md`, sin una representación física alternativa.

## Encabezado

```json
{
  "replay_version": 2,
  "geometry_contract_version": 1,
  "material_contract_version": 1,
  "session_id": "synthetic-08_merge",
  "synthetic_only": true,
  "tick_hz": 30,
  "scenario": "08_merge",
  "frames": []
}
```

Cada estado contiene:

- `session_id`: igual al encabezado, cadena no vacía de hasta 64 caracteres.
- `sequence`: entero creciente. Duplicados y estados antiguos se rechazan.
- `logical_time`: segundos lógicos no decrecientes, independientes del tiempo de procesamiento.
- `structures`: **estado completo**, no eventos diferenciales. Cada estructura conserva contrato, ID, geometría local, pose global, confianza, seguimiento, versión y `material_regions`.
- `identity_epochs`: diccionario de ID lógico → época entera positiva; exactamente las estructuras presentes.
- `region_identity_epochs`: ID de región → época entera positiva; exactamente las regiones presentes.
- `events`: MERGE/SPLIT con `type`, `parents`, `children`; son diagnóstico del cambio lógico. La geometría autoritativa siempre está en `structures`.
- `material_events`: diagnóstico del detector, incluidos creación, retiro, reasignación y ambigüedad de identidad regional. Se conserva en el archivo aunque no gobierna las colisiones.
- `diagnostic`: estado y número de fotograma fuente, más errores de procesamiento si existen.

Los materiales siguen llamándose `GREEN_SOLID`, `BLUE_BOUNCE`, `ORANGE_ONE_WAY`. El color no es el ID. Coordenadas locales y poses se interpretan según el contrato existente: píxeles de arena, X hacia la derecha, Y hacia abajo, ángulos en radianes. Los escenarios exportados parten de máscaras sintéticas de 640×480 dentro del viewport Godot 1280×720; no hay homografía ni escalado implícito. Los escenarios de movimiento/rotación pueden aplicar una pose rígida sintética a la geometría extraída por OpenCV; no representan una medición de cámara.

## Identidad y transacciones

La época de una región activa no cambia por pasar a otro propietario lógico durante MERGE/SPLIT. Un ID retirado que reaparece requiere una época mayor. Las versiones geométricas no retroceden; reutilizar una versión con otra geometría/material es inválido. Un cambio de propietario y un cambio de geometría se registran por separado.

Todos los estados de un archivo pertenecen a una sesión. Cargar otro archivo o reiniciar solicita un reset explícito en el límite de física antes de aceptar la nueva secuencia. El adaptador rechaza un cambio de sesión a mitad de reproducción. La sesión de los fixtures es determinista por escenario; un emisor personalizado puede usar el UUID generado por defecto por `MaterialReplayExporter`.

Se valida el objetivo completo antes de retirar o crear colisiones. Cada región física reutiliza `MaterialPhysicsManager` y `MaterialPolygonBody`. No se crea un collider adicional para la silueta lógica completa: así no aparece un volumen SOLID invisible sobre ONE_WAY. Las publicaciones APPLIED mantienen coherentes los mapas lógicos y los cuerpos regionales.

Un lote ocupado puede quedar DEFERRED. El reproductor no lo salta ni envía otro encima; espera a que sea seguro. No teletransporta al jugador. Reiniciar puede cancelar explícitamente el lote pendiente.

## Compatibilidad y límites

- El lector existente sigue aceptando `replay_version: 1` en el laboratorio anterior.
- En el laboratorio multimaterial, un archivo v1 se migra explícitamente: cada estructura antigua se convierte en una región `GREEN_SOLID`, con ID determinista derivado por SHA-256 del ID lógico. No se infiere rebote por el color de un archivo sin semántica material.
- Un backend antiguo sin soporte multimaterial rechaza archivos v2 explícitamente.
- Se rechazan encabezados incompatibles, sesiones mezcladas y material desconocido. No se reparan silenciosamente geometrías inválidas.
- Archivo máximo 32 MiB; entre 1 y 10000 estados por archivo. Emisor sintético: 30 estados/s; exportador configurable entre 1 y 60 Hz.
- Reproducción: 0,25×, 0,5×, 1× y 2× en la interfaz. Hay como máximo un estado por tick físico; no se omiten topologías para alcanzar una velocidad imposible.
- Pausa detiene la programación de nuevos estados y el movimiento hacia sus objetivos; no pausa jugadores ni combate. Un lote ya pendiente puede terminar cuando deje de ser inseguro.
- Eventos e historiales de error son acotados; los archivos contienen estados completos para recuperar la escena sin depender de recibir todos los eventos históricos.

## Exportación

Desde `C:\godot 4.6\juego frei`:

```powershell
python -m vision.material_replay --long-frames 1800
```

Genera 27 escenarios y un manifiesto en `juegofrei/validation/material_replays`. El escenario prolongado contiene 1800 estados, equivalentes a 60 segundos lógicos a 30 Hz. El coste de generar imágenes y procesarlas no es el tiempo de reproducción.

Exportar sólo un escenario, conservando las demás entradas del manifiesto:

```powershell
python -m vision.material_replay --scenario 27_orange_merge_split
```

Se puede usar `--scenario` varias veces y elegir `--output`. Los escenarios 23–25 contienen deliberadamente un duplicado, un estado antiguo y una geometría inválida para verificar rechazo y recuperación.
