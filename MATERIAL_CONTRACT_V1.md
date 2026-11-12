# Extensión local de materiales v1 — Fase 3B.1

Extensión aditiva del contrato geométrico **Fase 1C v1**. No cambia el protocolo
UDP 3A, ni CAMERA/PROJECTOR, ni sus emisores/receptores de producción. No se envían
estos datos por red en esta fase. No hay comportamiento físico nuevo.

## Dos niveles

**Estructura lógica:** conserva `id`, pose, `geometry_version`, `regions`,
`convex_parts`, seguimiento, confianza y todos los campos anteriores. Las épocas
de identidad se mantienen en `identity_epochs[id]` del snapshot completo, igual
que en Fase 1D. El ID no es el color. La pose es un ancla, no necesariamente el
centroide físico.

**Región de material:** una estructura agrega `material_contract_version=1` y una
lista `material_regions`. Cada elemento contiene:

```json
{
  "region_id": "r00000001",
  "structure_id": "s000001",
  "material": "GREEN_SOLID",
  "geometry_version": 1,
  "regions": [
    {"exterior": [[0,0],[30,0],[30,30],[0,30]], "holes": []}
  ],
  "convex_parts": [[[0,0],[30,0],[30,30],[0,30]]]
}
```

El ejemplo es una región aislada; en una estructura mayor deben incluirse todas
las regiones necesarias para cubrir exactamente su silueta. Cada región hereda
la pose de su estructura: **no tiene otra transformación global independiente**.
Los vértices de todas las regiones se expresan en el mismo espacio local del
propietario. No se aplica dos veces la posición.

Se reutilizan exactamente `regions/exterior/holes` y `convex_parts` de Fase 1C;
no hay una segunda representación de polígonos. Una región conectada por una
esquina puede tener varios exteriores simples bajo un único `region_id`.

## Convenciones y materiales

* Coordenadas: `ARENA_PIXELS`, píxeles, X derecha / Y abajo, ángulos en radianes.
* Exteriores con área firmada positiva (sentido horario en pantalla); agujeros
  con área negativa. Vértices ordenados, sin repetir el primero al final.
* Las formas se obtienen de bordes de celdas de píxel, no de sus centros.
* En la fuente sintética se mantiene `orientation_radians=0`, igual que la
  política anterior de contornos alineados al mundo. No se inventa el ángulo
  del compuesto a partir del de uno de sus materiales.
* El exportador elige un ancla entera y rebasa **tanto** la silueta general
  **como** los materiales. Sus bordes globales no cambian. Así se evita la
  cancelación float32 de centroides fraccionarios en clipping de Godot.
* El mapeo sigue siendo `IDENTITY_SYNTHETIC_LAB_ONLY`. No representa una
  calibración de cámara/proyector ni habilita usar coordenadas físicas crudas.

| Color de segmentación | Identificador del contrato, compatible con la reserva 3A | Regla futura |
|---|---|---|
| Verde, etiqueta 1 | `GREEN_SOLID` (SOLID) | Sólido en todas sus caras |
| Azul, etiqueta 2 | `BLUE_BOUNCE` (BOUNCE) | Rebote según la normal real de contacto |
| Naranja, etiqueta 3 | `ORANGE_ONE_WAY` (ONE_WAY) | Atraviesa desde abajo/laterales; descenso con abajo estando apoyado |

Las etiquetas HSV 1/2/3 no son IDs de estructura ni IDs de región. No se deduce
material de `region_id`. La física de esta tabla **no está implementada**.

## Versiones, identidad y validación

1. `contract_version` permanece en 1. `material_contract_version` es una extensión
   independiente; versiones desconocidas se rechazan. El contrato antiguo sin
   extensión sigue siendo válido para consumidores antiguos.
2. La geometría general se conserva para compatibilidad y validación. Un futuro
   backend material-aware debe crear las colisiones de los materiales; **no debe
   crear simultáneamente una colisión sólida de la unión general**, porque
   duplicaría superficies y anularía ONE_WAY/BOUNCE.
3. `region_id` es único entre las regiones activas de una instancia/sesión de
   seguimiento. Es serial, independiente del color y no se recicla tras retirarlo.
   Si cambia el material de una región se crea una identidad nueva.
4. Cambiar propietario durante MERGE/SPLIT conserva el ID regional si la evidencia
   geométrica y de material es mutuamente única. Un rebase que cambie los vértices
   locales incrementa su revisión. La pose sola no reconstruye la geometría.
5. En uniones/separaciones no únicas del mismo material se crean IDs nuevos y se
   registra `REGION_IDENTITY_AMBIGUITY`. No se fuerza una correspondencia.
6. La revisión de estructura considera la silueta **y** la partición material.
   Cambiar el límite/material sin cambiar el contorno exterior también incrementa
   `geometry_version`. Se reutiliza el ledger de snapshots de Fase 1D. Las épocas
   aumentan al recuperar un ID de estructura retirado; sus revisiones no retroceden.
7. Materiales desconocidos, IDs vacíos/duplicados, propietario incorrecto,
   revisiones inválidas y regiones vacías se rechazan. No hay fallback físico
   automático a SOLID.
8. La unión de materiales debe cubrir exactamente la silueta aceptada, sin
   superposiciones ni rellenar agujeros. Los huecos interiores son fondo y no
   reciben material ni partes convexas.
9. Python comprueba cobertura/disjunción en máscaras exactas durante la creación,
   usa el constructor geométrico existente y valida esquema/anillos. El validador
   Godot adicional reutiliza el validador compuesto completo y verifica áreas,
   contención, convexidad, agujeros y solapamientos entre regiones. La comprobación
   Python de esquema no sustituye esa validación de polígonos importados arbitrarios.
10. Ante un rechazo o partición pendiente, se conserva el snapshot completo anterior
    con seguimiento HELD. No se publica una mezcla parcial de geometrías viejas y
    materiales nuevos. El ID serial puede quedar consumido en un rechazo; nunca
    se reutiliza para otro objeto.

Límites iniciales: 128 regiones de material, 512 partes convexas de material
agregadas, presupuesto de contornos heredado de Fase 1C y límite de imagen de
`StructureSettings`. La caché exacta está acotada por cantidad de regiones; no es
una garantía de memoria RSS para imágenes máximas y contornos extremos.

## Máscaras y confirmación

Se conservan máscaras HSV crudas independientes para diagnóstico. La clasificación
material es exclusiva: todo píxel presente en más de una máscara queda excluido
de **todos** los materiales y se registra en `conflict_mask/conflict_pixels`.
No hay prioridad por orden de colores. La unión lógica se calcula después de
esa exclusión y del filtrado de componentes pequeños.

Los contactos usan conectividad 8. El tracker anterior conserva sus reglas de
contacto confirmado, esquina, proximidad ambigua, MERGE/SPLIT y pérdidas. No se
dilata para inventar puentes. Apertura morfológica optativa 0/3/5; por defecto 0
para conservar regiones de un píxel de espesor. No se realiza cierre que rellene
agujeros o separaciones. `min_area` por color rechaza ruido aislado.

La confirmación material inicial es de tres frames. Se suma a la confirmación
topológica cuando corresponda: por defecto primera publicación en el frame 5;
contacto por esquina en el frame 7. Son cantidades de frames, **no** una latencia
de tiempo real garantizada. La velocidad medida puede ser inferior a 30 Hz.

El pipeline multimaterial exige siluetas exactas al compararlas con los materiales
(`geometry_difference_fraction=0` solo en esta instancia). No cambia los defaults
del tracker anterior. Una variación de silueta solo se publica con su partición
confirmada; no se modifica la geometría física de ningún personaje o plataforma.

## Archivos offline y compatibilidad

`vision.material_lab --headless --export ...` produce un archivo de diagnóstico
`material_snapshot_file_version=1`, `geometry_contract_version=1`,
`material_contract_version=1`, `synthetic_only=true`, escenario, frecuencia y
snapshots completos con secuencia, tiempo lógico, épocas, estructuras y eventos.
Conserva el formato geométrico anterior dentro de cada estructura.

Este sobre de diagnóstico se identifica por separado para que el reproductor
físico antiguo no lo aplique accidentalmente como colisiones sólidas
indiferenciadas. El exportador/reproductor offline anteriores permanecen disponibles
y sus suites se ejecutaron. La adaptación física material-aware queda pendiente.

Los eventos lógicos MERGE/SPLIT se mantienen; los eventos locales de región son
`REGION_CREATE`, `REGION_REMOVE`, `REGION_REPARENT` y
`REGION_IDENTITY_AMBIGUITY`. En una pérdida breve se conserva la identidad; tras
una retirada confirmada, regiones nuevas no recuperan IDs retirados sin evidencia.

No se modificó ni se conectó este archivo al transporte UDP. Los campos básicos
de la reserva `material_regions` de 3A conservan su significado; los identificadores
y revisiones son metadatos adicionales. La integración posterior debe exigir la
versión de extensión y el validador material-aware antes del commit físico.
