from pathlib import Path
import math
from xml.sax.saxutils import escape
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph, Table, TableStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pypdf import PdfReader, PdfWriter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/pdf/proyecto mys - completo.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)
BODY = ROOT / 'tmp/pdfs/documento_armado.pdf'
W,H = 596,842
M = 48
CW = W-2*M
BLUE = colors.HexColor('#173D65')
INK = colors.HexColor('#20252B')
GRAY = colors.HexColor('#5B626B')
LINE = colors.HexColor('#BBC3CC')
TINT = colors.HexColor('#F1F5F9')
for name,file in [('Arial','arial.ttf'),('Arial-Bold','arialbd.ttf'),('Arial-Italic','ariali.ttf')]:
    pdfmetrics.registerFont(TTFont(name,str(Path('C:/Windows/Fonts')/file)))
pdfmetrics.registerFontFamily('Arial',normal='Arial',bold='Arial-Bold',italic='Arial-Italic',boldItalic='Arial-Bold')

c=canvas.Canvas(str(BODY),pagesize=(W,H))
c.setTitle('Documentación de requerimientos de negocio: Sistema de reconocimiento de arenas modulares')
c.setAuthor('Barrios Tiziano; Lucero Alan; Ramírez Emanuel; Martínez Benjamín; Rea Lourdes')
c.setSubject('Modelos y Sistemas - Bases de Datos')

def paragraph(text,x,y,width=CW,size=10.7,leading=14.3,bold=False,color=INK,align=0):
    style=ParagraphStyle('local',fontName='Arial-Bold' if bold else 'Arial',fontSize=size,
                         leading=leading,textColor=color,alignment=align,spaceAfter=0)
    p=Paragraph(text,style)
    _,height=p.wrap(width,1000)
    p.drawOn(c,x,y-height)
    return y-height

def page(number):
    c.setFillColor(GRAY); c.setFont('Arial',8.3)
    c.drawString(M,H-32,'Sistema de reconocimiento de arenas modulares')
    c.setStrokeColor(LINE);c.setLineWidth(.5);c.line(M,H-42,W-M,H-42)
    c.line(M,40,W-M,40)
    c.drawString(M,26,'Documentación de requerimientos de negocio | Versión 1.0')
    c.drawRightString(W-M,26,str(number))

def heading(text,y,level=1):
    return paragraph(escape(text),M,y,size=15 if level==1 else 11.7,
                     leading=19 if level==1 else 15.8,bold=True,color=BLUE)-7

def body(text,y):
    return paragraph(text,M,y)-8

def item(code,text,y):
    return paragraph(f'<b>{code}</b> {text}',M,y)-5

def finish(y=None):
    if y is not None and y<54:
        raise ValueError(f'Page content below footer: {y}')
    c.showPage()

def label(text,x,y,width=120,size=9.4,background=True):
    style=ParagraphStyle('label',fontName='Arial',fontSize=size,leading=size+2.3,textColor=INK,alignment=1)
    p=Paragraph(text,style);_,h=p.wrap(width,500)
    if background:
        c.setFillColor(colors.white);c.rect(x-width/2-3,y-h/2-2,width+6,h+4,fill=1,stroke=0)
    p.drawOn(c,x-width/2,y-h/2)

def box(x,y,w,h,title,subtitle='',rounded=True):
    c.setStrokeColor(BLUE);c.setLineWidth(1);c.setFillColor(TINT)
    if rounded:c.roundRect(x,y,w,h,8,fill=1,stroke=1)
    else:c.rect(x,y,w,h,fill=1,stroke=1)
    top=y+h-12
    top=paragraph(title,x+8,top,w-16,size=10.4,leading=13,bold=True,align=1)
    if subtitle:
        paragraph(subtitle,x+8,top-5,w-16,size=9.2,leading=11.8,align=1)

def arrow(points,text=None,text_at=None,width=115,dashed=False):
    c.setStrokeColor(GRAY);c.setLineWidth(.9)
    c.setDash(4,3) if dashed else c.setDash()
    p=c.beginPath();p.moveTo(*points[0])
    for pt in points[1:]:p.lineTo(*pt)
    c.drawPath(p)
    c.setDash()
    x,y=points[-1];px,py=points[-2]
    theta=math.atan2(y-py,x-px);length=6
    path=c.beginPath();path.moveTo(x,y)
    path.lineTo(x-length*math.cos(theta-.5),y-length*math.sin(theta-.5))
    path.lineTo(x-length*math.cos(theta+.5),y-length*math.sin(theta+.5));path.close()
    c.setFillColor(GRAY);c.drawPath(path,fill=1,stroke=0)
    if text:label(text,*text_at,width=width)

def entity(x,y,w,h,title,fields):
    c.setStrokeColor(BLUE);c.setLineWidth(1);c.setFillColor(colors.white);c.rect(x,y,w,h,fill=1,stroke=1)
    c.setFillColor(TINT);c.rect(x,y+h-29,w,29,fill=1,stroke=0)
    c.setStrokeColor(BLUE);c.line(x,y+h-29,x+w,y+h-29)
    paragraph(title,x+7,y+h-8,w-14,size=10.2,leading=12,bold=True,align=1)
    paragraph('<br/>'.join(fields),x+10,y+h-40,w-20,size=9.5,leading=15)

def store(x,y,w,h,title,subtitle):
    c.setStrokeColor(BLUE);c.setLineWidth(1)
    c.line(x,y,x,y+h);c.line(x,y+h,x+w,y+h);c.line(x,y,x+w,y)
    top=paragraph(title,x+6,y+h-11,w-12,size=10.1,leading=12.5,bold=True,align=1)
    paragraph(subtitle,x+6,top-5,w-12,size=9.2,leading=11.8,align=1)

def table(headers,rows,widths,y,font=10):
    def cell(t,bold=False):
        return Paragraph(t,ParagraphStyle('cell',fontName='Arial-Bold' if bold else 'Arial',fontSize=font,
                                         leading=font+3.5,textColor=INK))
    data=[[cell(h,True) for h in headers]]+[[cell(s) for s in row] for row in rows]
    t=Table(data,colWidths=widths,hAlign='LEFT')
    t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),TINT),('GRID',(0,0),(-1,-1),.5,LINE),
                           ('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),8),
                           ('RIGHTPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),7),
                           ('BOTTOMPADDING',(0,0),(-1,-1),7)]))
    _,height=t.wrap(CW,1000);t.drawOn(c,M,y-height)
    return y-height

# 1. Cover: same school logo, members, subjects, professor, date and system name
# as the supplied original. Re-typeset to preserve searchable accented text.
y=paragraph('Documentación de requerimientos de negocio:<br/>Sistema de reconocimiento de arenas modulares',
            65,765,W-130,size=17,leading=23,bold=True,color=INK,align=1)
logo=next((ROOT/'tmp/pdfs').glob('proyecto_1_0_*.png'))
c.drawImage(str(logo),(W-168)/2,480,width=168,height=168,mask='auto')
y=440
y=paragraph('<b>CARRERA:</b> Tecnicatura informática personal y profesional.',76,y,W-152)-12
y=paragraph('<b>Versión:</b> 1.0<br/><b>Fecha de entrega:</b> 05/11/2026',76,y,W-152)-18
y=paragraph('<b>MATERIAS</b><br/>Modelos y Sistemas<br/>Bases de Datos',76,y,W-152)-18
y=paragraph('<b>INTEGRANTES</b>',76,y,W-152)-5
for name in ['Barrios Tiziano','Lucero Alan','Ramírez Emanuel','Martínez Benjamín','Rea Lourdes']:
    y=paragraph('• '+name,88,y,W-176)-3
y=paragraph('<b>PROFESOR:</b> Freisz Cristian.',76,y-14,W-152)
finish(y)

# 2. Exact required table of contents, on the second page.
page(2);y=heading('Tabla de contenidos',774)
toc=[('1. Introducción',3,0),('2. Alcance',3,0),('2.1. Sistema y justificación',3,1),
     ('2.2. Objetivos del proyecto',3,1),('2.3. Beneficios',3,1),('2.4. Alcances del sistema',3,1),
     ('3. Reglas del negocio',3,0),('4. Requerimientos del sistema',4,0),('4.1. Actores',4,1),
     ('4.2. Requerimientos funcionales',4,1),('4.3. Requerimientos no funcionales',4,1),
     ('4.4. User story',5,1),('5. Diagramas',5,0),('5.1. Diagrama de flujo de datos',5,1),
     ('5.2. Diagrama de casos de uso',6,1),('5.3. Diagrama de transición de estados',7,1),
     ('5.4. Diagrama Entidad Relación',8,1),('6. Prototipo',9,0)]
for title,number,depth in toc:
    x=M+14*depth
    c.setFont('Arial-Bold' if not depth else 'Arial',11)
    c.setFillColor(INK);c.drawString(x,y-15,title)
    c.setFont('Arial',11);c.drawRightString(W-M,y-15,str(number))
    c.setStrokeColor(colors.HexColor('#DBDFE4'));c.setLineWidth(.35);c.line(x,y-24,W-M,y-24)
    y-=31
finish(y)

# 3. Introduction, scope and rules: no unrequested chapters.
page(3);y=heading('1. Introducción',774)
y=body('El sistema vincula módulos físicos de colores con plataformas de una arena de combate 2D. '
       'Una webcam captura los módulos; Python y OpenCV reconocen su posición y orientación y las envían a Godot. '
       'Dos jugadores compiten en la misma computadora mientras un operador modifica el escenario.',y)
y=heading('2. Alcance',y-3)
y=heading('2.1. Sistema y justificación',y,2)
y=body('Permite cambiar la disposición de una arena virtual mediante objetos físicos o mouse. '
       'La propuesta integra visión artificial y videojuegos para ofrecer interacción tangible y '
       'aplicar contenidos de análisis de sistemas, programación y modelado de datos.',y)
y=heading('2.2. Objetivos del proyecto',y,2)
y=body('Reconocer los módulos verde y azul con IDs estables; actualizar únicamente la posición y '
       'rotación de sus plataformas; permitir el combate local y preparar la correspondencia geométrica '
       'entre cámara y proyección.',y)
y=heading('2.3. Beneficios',y,2)
y=body('Arena reconfigurable sin redibujar el escenario; participación de un tercer usuario; '
       'calibración ajustable a la iluminación y control manual disponible para pruebas.',y)
y=heading('2.4. Alcances del sistema',y,2)
y=body('Incluye dos jugadores, combate, menús, control MOUSE/EXTERNAL, detección por color, '
       'seguimiento, comunicación UDP local y calibración HSV y geométrica. '
       'La salida con proyector está preparada por software; falta validarla físicamente sobre una pared. '
       'No incluye juego en red, cuentas de usuario ni modificación de la forma o tamaño de las plataformas.',y)
y=heading('3. Reglas del negocio',y-3)
rules=[('RN01.','Verde corresponde al ID 1 y a left; azul al ID 2 y a right. La plataforma top no tiene módulo de color asignado.'),
       ('RN02.','Solo se modifican plataformas predefinidas. Cada una conserva su forma y tamaño.'),
       ('RN03.','MOUSE y EXTERNAL son excluyentes; una plataforma no recibe órdenes simultáneas de ambas fuentes.'),
       ('RN04.','Una detección nueva debe confirmarse. Ante pérdida de seguimiento se conserva la última pose válida y se detiene el movimiento.'),
       ('RN05.','Cada jugador inicia con tres vidas. Al salir de los límites pierde una; gana quien conserva vidas. La eliminación final simultánea produce empate.'),
       ('RN06.','Solo se aceptan IDs conocidos y datos válidos y recientes. Una calibración geométrica inválida no se guarda.')]
for code,text in rules:y=item(code,text,y)
finish(y)

# 4. Actors and indispensable requirements.
page(4);y=heading('4. Requerimientos del sistema',774)
y=heading('4.1. Actores',y,2)
y=table(['Actor','Responsabilidad'],[
    ('Jugador 1 y jugador 2','Iniciar la partida, moverse, saltar, atacar, esquivar, consultar controles y pausar/reiniciar.'),
    ('Operador','Calibrar la visión y la proyección; elegir la fuente de control; mover módulos físicos o editar plataformas con mouse.'),
    ('Webcam USB','Fuente externa de imágenes para el reconocimiento y la calibración.')],[145,355],y)-16
y=heading('4.2. Requerimientos funcionales',y,2)
functional=[('RF01.','Permitir jugar a dos personas simultáneamente con controles de teclado independientes.'),
 ('RF02.','Gestionar movimiento, saltos, ataques, esquiva, daño acumulado, vidas, reaparición, victoria o empate y reinicio.'),
 ('RF03.','Ofrecer menú principal, pantalla de controles, pausa y regreso al menú.'),
 ('RF04.','Seleccionar, mover y rotar plataformas con mouse, o recibir sus objetivos desde visión, según el modo activo.'),
 ('RF05.','Detectar verde y azul por separado; validar candidatos, confirmar el seguimiento y evitar cruces de IDs.'),
 ('RF06.','Permitir ajustar, guardar y cargar los rangos HSV; mostrar máscaras, candidatos y estado por módulo.'),
 ('RF07.','Calcular y validar una homografía con referencias automáticas o manuales; transformar centro y orientación en modo PROJECTOR.'),
 ('RF08.','Recibir UDP local, rechazar datos inválidos o atrasados y congelar módulos perdidos sin alterar su geometría.')]
for code,text in functional:y=item(code,text,y)
y=heading('4.3. Requerimientos no funcionales',y-5,2)
nonfunctional=[('RNF01.','Ejecutar en Windows con Godot 4.6.3, Python 3, OpenCV y NumPy.'),
 ('RNF02.','Usar resolución lógica 1280 × 720 y física a 60 ticks/s. Objetivos: juego a 60 FPS y visión cercana a 30 FPS, sujetos al hardware.'),
 ('RNF03.','Procesar la comunicación sin bloquear el juego y suavizar las transformaciones con límites de velocidad.'),
 ('RNF04.','Mantener visión, comunicación, plataformas y combate desacoplados; persistir la configuración en JSON.'),
 ('RNF05.','Informar estado de conexión, seguimiento y errores; rechazar calibraciones incompatibles con la captura.')]
for code,text in nonfunctional:y=item(code,text,y)
finish(y)

# 5. User stories + DFD Level 1.
page(5);y=heading('4.4. User story',774,2)
y=table(['ID','Historia'],[
 ('US01','Como jugador, quiero moverme y combatir con otro jugador para disputar una partida local.'),
 ('US02','Como operador, quiero que cada módulo controle solo su plataforma para modificar la arena sin interferencias.'),
 ('US03','Como operador, quiero calibrar colores y proyección para adaptar el reconocimiento al entorno.'),
 ('US04','Como operador, quiero que una plataforma se detenga al perder seguimiento para evitar movimientos inesperados.')],[49,451],y,font=10)-17
y=heading('5. Diagramas',y)
y=heading('5.1. Diagrama de flujo de datos',y,2)
diagram_top=y-5
# Fixed diagram coordinates below the stories; all flows name their data.
box(48,410,100,50,'Webcam USB','Imágenes',False)
box(205,400,180,70,'1. Reconocer y seguir','HSV, filtros y confirmación')
arrow([(148,435),(205,435)],'Imagen',(176,453),width=50)
store(445,402,103,66,'D1. Configuración','HSV y seguimiento')
arrow([(385,450),(445,450)],'Guardar',(415,464),width=48)
arrow([(445,419),(385,419)],'HSV',(415,432),width=40)
box(205,280,180,70,'2. Calibrar y transformar','CAMERA o PROJECTOR')
arrow([(295,400),(295,350)],'ID, centro, ángulo<br/>y visibilidad',(295,375),width=145)
store(445,281,103,68,'D2. Calibración','Homografía y puntos')
arrow([(385,330),(445,330)],'Guardar',(415,345),width=48)
arrow([(445,300),(385,300)],'H y puntos',(415,314),width=48)
box(48,280,100,70,'Operador','Parámetros y<br/>correspondencias',False)
arrow([(98,350),(98,384),(178,384),(178,414),(205,414)],'Ajustes HSV',(103,377),width=90)
arrow([(148,315),(205,315)],'Puntos',(176,333),width=44)
box(205,163,180,70,'3. Validar y actualizar arena','UDP, ID y objetivos físicos')
arrow([(295,280),(295,233)],'JSON por UDP local',(295,257),width=140)
arrow([(148,293),(171,293),(171,198),(205,198)],'Mouse',(171,245),width=46)
box(205,66,180,60,'4. Ejecutar la partida','Combate, física e interfaz')
arrow([(295,163),(295,126)],'Transformaciones',(295,145),width=130)
box(445,69,103,56,'Jugadores','Entradas y resultado',False)
arrow([(445,108),(385,108)],'Teclas',(415,121),width=44)
arrow([(385,83),(445,83)],'Vista',(415,94),width=44)
finish(60)

# 6. Use cases. Solid lines are actor associations, not data flows.
page(6);y=heading('5.2. Diagrama de casos de uso',774,2)
y=body('Los jugadores usan el videojuego. El operador configura la visión y elige cómo controlar la arena.',y)
c.setStrokeColor(BLUE);c.setLineWidth(1);c.rect(170,104,290,570)
paragraph('Sistema de reconocimiento<br/>de arenas modulares',182,661,266,size=11,bold=True,align=1)
def actor(x,y,name):
    c.setStrokeColor(INK);c.setLineWidth(1.1);c.circle(x,y+30,10,fill=0)
    c.line(x,y+20,x,y-11);c.line(x-19,y+6,x+19,y+6);c.line(x,y-11,x-17,y-34);c.line(x,y-11,x+17,y-34)
    paragraph(name,x-58,y-43,116,size=10,leading=13,align=1)
def usecase(center_y,title):
    c.setFillColor(TINT);c.setStrokeColor(BLUE);c.ellipse(205,center_y-23,425,center_y+23,fill=1,stroke=1)
    label(title,315,center_y,width=190,size=10.3,background=False)
def assoc(points):
    c.setStrokeColor(GRAY);c.setLineWidth(.8);p=c.beginPath();p.moveTo(*points[0])
    for xy in points[1:]:p.lineTo(*xy)
    c.drawPath(p)
actor(91,533,'Jugador<br/>(1 o 2)')
actor(505,330,'Operador')
for yy,title in [(598,'Jugar una partida'),(530,'Pausar / reanudar'),(462,'Reiniciar / volver al menú'),
                  (380,'Controlar arena con mouse'),(312,'Controlar arena con visión'),(244,'Calibrar colores'),(176,'Calibrar proyección')]:
    usecase(yy,title)
for yy in (598,530,462):assoc([(111,539),(145,539),(145,yy),(205,yy)])
for yy in (380,312,244,176):assoc([(485,336),(444,336),(444,yy),(425,yy)])
box(49,196,96,56,'Webcam USB','Fuente externa',False)
assoc([(145,224),(156,224),(156,312),(205,312)])
assoc([(145,211),(161,211),(161,176),(205,176)])
paragraph('La webcam participa en el seguimiento y la calibración. MOUSE y EXTERNAL son alternativas de control excluyentes.',
          M,81,CW,size=10,leading=13)
finish(55)

# 7. State transition model of the central recognition function.
page(7);y=heading('5.3. Diagrama de transición de estados',774,2)
y=body('Seguimiento temporal de un módulo en Python. Los umbrales indicados corresponden a la configuración actual.',y)
nodes=[(190,614,216,64,'Adquisición','Confirma candidatos coherentes'),
       (190,466,216,64,'En seguimiento','Actualiza la pose suavizada'),
       (190,318,216,64,'Retención','Conserva la última pose válida'),
       (190,170,216,64,'Perdido','visible = false; no extrapola')]
for args in nodes:box(*args)
c.setFillColor(INK);c.circle(298,703,5,fill=1,stroke=0)
arrow([(298,698),(298,678)])
arrow([(298,614),(298,530)],'3 detecciones<br/>coherentes',(345,572),width=130)
arrow([(298,466),(298,382)],'Sin observación válida<br/>por más de 60 ms',(352,424),width=150)
arrow([(298,318),(298,234)],'Más de 150 ms desde<br/>la última observación válida',(356,276),width=178)
arrow([(190,350),(104,350),(104,498),(190,498)],'Detección recuperada<br/>antes de 150 ms',(102,424),width=115)
arrow([(406,202),(499,202),(499,646),(406,646)],'Nueva detección:<br/>volver a confirmar',(488,573),width=112)
arrow([(190,646),(144,646),(144,687),(231,687),(231,678)],'Candidato aislado<br/>o incoherente',(114,700),width=128)
paragraph('Una detección aislada no activa una plataforma nueva. Desde Perdido se exige nueva confirmación; '
          'los límites físicos de Godot evitan saltos bruscos. Si se detiene el emisor, el receptor '
          'también congela las plataformas al vencer su tiempo de espera.',M,123,CW,size=10.4,leading=14)
finish(64)

# 8. Conceptual ER: intentionally no fabricated SQL implementation or match DB.
page(8);y=heading('5.4. Diagrama Entidad Relación',774,2)
y=body('Modelo conceptual de los datos del sistema. Actualmente se utilizan escenas, estado en memoria y archivos JSON; '
       'no hay una base de datos relacional implementada.',y)
entity(48,515,205,143,'MÓDULO',['<b>PK</b> id_módulo','<b>FK</b> id_plataforma','posición observada','ángulo observado','visible / última observación'])
entity(350,515,198,143,'PLATAFORMA',['<b>PK</b> id_plataforma','posición y rotación','forma y tamaño fijos','estado de detección'])
entity(48,270,205,157,'PERFIL HSV',['<b>PK, FK</b> id_módulo','nombre del color','HSV mínimo / máximo','área y dimensiones admitidas','confianza mínima'])
entity(326,303,222,156,'CALIBRACIÓN',['<b>PK</b> id_calibración','resolución de captura / salida','matriz de homografía','fecha y errores','cámara, backend y espejo'])
entity(326,92,222,151,'CORRESPONDENCIA',['<b>PK, FK</b> id_calibración','<b>PK</b> tipo + índice','punto de cámara (x, y)','punto de proyección (x, y)','tipo: ajuste / verificación'])
c.setStrokeColor(GRAY);c.setLineWidth(.9)
c.line(253,585,350,585);label('asocia',301,609,width=80)
label('0..1',268,571,width=28);label('1',335,571,width=20)
c.line(150,515,150,427);label('configura',150,471,width=90)
label('1',163,505,width=20);label('1',163,438,width=20)
c.line(437,303,437,243);label('contiene',437,275,width=80)
label('1',456,296,width=20);label('N',456,250,width=20)
paragraph('PK: clave primaria conceptual.<br/>FK: referencia a otra entidad.<br/><br/>'
          'Un módulo controla una plataforma. Una plataforma puede no tener módulo de color.<br/><br/>'
          'La calibración utiliza 8 correspondencias: 4 de ajuste y 4 de verificación.',48,227,205,size=10,leading=14)
paragraph('Las claves son conceptuales: el ID de calibración identifica el archivo; tipo e índice identifican los puntos en sus listas.',
          M,78,CW,size=9.4,leading=12)
finish(54)

# 9. Prototype, only genuine captures/assets from the inspected project.
page(9);y=heading('6. Prototipo',774)
y=body('Prototipo local implementado con Godot 4.6.3 y Python/OpenCV. Incluye dos jugadores, '
       'tres vidas, combate, menús y plataformas controladas por mouse o visión.',y)
image_y=y-281
c.drawImage(str(ROOT/'artifacts/udp_simulation.png'),M,image_y,width=500,height=281.25)
c.setStrokeColor(LINE);c.rect(M,image_y,500,281.25,fill=0)
y=paragraph('<b>Arena y diagnóstico.</b> Captura del proyecto en EXTERNAL con el emisor detenido: '
            'las plataformas conservan su última pose y se informa la pérdida de comunicación.',M,image_y-8,CW,size=9.7,leading=13)-17
thumb_h=135
thumb_y=y-thumb_h
c.drawImage(str(ROOT/'artifacts/qa_menu.png'),M,thumb_y,width=240,height=thumb_h)
c.drawImage(str(ROOT/'juegofrei/calibration/projector_pattern.png'),M+260,thumb_y,width=240,height=thumb_h)
c.setStrokeColor(LINE);c.rect(M,thumb_y,240,thumb_h,fill=0);c.rect(M+260,thumb_y,240,thumb_h,fill=0)
paragraph('<b>Menú principal.</b> Acceso a partida y controles.',M,thumb_y-8,240,size=9.5,leading=12)
paragraph('<b>Patrón de calibración.</b> Referencias de ajuste y verificación.',M+260,thumb_y-8,240,size=9.5,leading=12)
y=thumb_y-53
y=body('<b>Uso básico:</b> jugador 1: A/D, W/S, F/G/H; jugador 2: flechas, K/L y Shift derecho. '
       'Esc pausa; F2 alterna MOUSE/EXTERNAL. El detector se inicia con RunDetector.cmd.',y)
y=body('<b>Estado:</b> se comprobó el reconocimiento físico de verde y azul por separado y la integración '
       'de software. Sigue pendiente validar el seguimiento simultáneo estable y la alineación física '
       'con proyector sobre la pared definitiva.',y)
finish(y)

c.save()
reader=PdfReader(BODY)
assert len(reader.pages)==9
writer=PdfWriter();writer.append(reader)
writer.add_metadata({'/Title':'Documentación de requerimientos de negocio: Sistema de reconocimiento de arenas modulares',
                     '/Author':'Barrios Tiziano; Lucero Alan; Ramírez Emanuel; Martínez Benjamín; Rea Lourdes',
                     '/Subject':'Modelos y Sistemas - Bases de Datos', '/Keywords':'arenas modulares, requerimientos, diagramas, Godot, OpenCV'})
for title,p,_ in toc:
    writer.add_outline_item(title,p-1)
with OUT.open('wb') as output:writer.write(output)
print(OUT)
print('Páginas:',len(reader.pages))
