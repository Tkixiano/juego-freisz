extends Node2D
@onready var receiver: Node = $Receiver
@onready var display: Label = $Canvas/Status
var refresh: float = 0
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("101925"))
	queue_redraw()
func _process(delta: float) -> void:
	refresh -= delta
	if refresh>0: return
	refresh = 0.2
	var s: Dictionary = receiver.get_status()
	display.text = "FASE 3A · LABORATORIO UDP DE ESTRUCTURAS\n\nSin conexión al administrador físico ni al combate.\nEscucha: %s:%s · activa: %s · error: %s\n\nEstado: %s · secuencia: %s\nSesión: %s\nEstructuras: %s · antigüedad local: %s ms\nMensajes aceptados: %s · rechazos: %s · fragmentos vencidos: %s\nReensamblados pendientes: %s · memoria reservada: %s B\nMERGE: %s · SPLIT: %s\n\nSCENE_EMPTY requiere un snapshot completo confirmado.\nUn timeout produce SCENE_STALE; conserva el último estado.\nNo se generan colisiones ni piso de seguridad en esta fase.\n\nEmisor: python -m vision.structure_udp_sender\nCerrar esta escena libera el puerto 5015." % [s.bind_ip,s.port,s.listening,s.bind_error,s.scene_state,s.sequence,s.session_id,s.objects,s.age_ms,s.metrics.accepted,s.metrics.rejected,s.metrics.expired,s.pending_messages,s.reserved_bytes,s.metrics.merges,s.metrics.splits]
