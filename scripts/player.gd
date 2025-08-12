extends CharacterBody3D

@onready var camera_3d: Camera3D = $Camera3D
@onready var name_label: Label3D = $NameLabel
@onready var spawn_position: Marker3D = $/root/MainScene/Players/SpawnPosition
@onready var audio_network_player: AudioStreamPlayer3D = $AudioNetworkPlayer

@export var player_name: String = "Terry"
@export var steam_id: int = 0
@export_range(0, 20) var audio_amplification: float = 5.0

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

const Net = preload("res://scripts/net_p2p.gd")

var mouse_locked: bool = false
var look_sensitivity: float = 0.01

func _ready() -> void:
	add_to_group("players")
	
	if is_multiplayer_authority():
		camera_3d.set_current(true)
		player_name = SteamManager.STEAM_USERNAME
		steam_id = SteamManager.STEAM_ID
		name_label.text = ""
	else:
		steam_id = multiplayer.multiplayer_peer.get_steam64_from_peer_id(get_multiplayer_authority())
		player_name = Steam.getFriendPersonaName(steam_id)
		name_label.text = player_name
	
	if get_window().has_focus():
		_on_window_focus()
	get_window().focus_entered.connect(_on_window_focus)
	
func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		return
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func _input(event: InputEvent) -> void:
	if !is_multiplayer_authority():
		return
	if event.is_action("Unstuck"):
		transform.origin = spawn_position.transform.origin
		velocity = Vector3.ZERO
	elif event.is_action_pressed("ui_cancel"):
		mouse_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if event is InputEventMouseMotion:
		if get_window().has_focus() and mouse_locked:
			var diff = -event.screen_relative
			rotate_y(diff.x * look_sensitivity)
			camera_3d.rotate_object_local(Vector3.RIGHT, diff.y * look_sensitivity)
			camera_3d.rotation.x = clamp(camera_3d.rotation.x, deg_to_rad(-90.0), deg_to_rad(90.0))
	if event is InputEventMouseButton:
		if !mouse_locked:
			_on_window_focus()
		
func _on_window_focus():
	mouse_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
