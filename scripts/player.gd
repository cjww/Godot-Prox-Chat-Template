extends CharacterBody3D

@onready var camera_3d: Camera3D = $Camera3D
@onready var name_label: Label3D = $NameLabel
@onready var prox_network: AudioStreamPlayer3D = $ProxNetwork
@onready var prox_local: AudioStreamPlayer3D = $ProxLocal

@export var player_name: String = "Terry"
@export var steam_id: int = 0

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

const Net = preload("res://scripts/net_p2p.gd")

var current_sample_rate: int = 48000
var has_loopback: bool = false
var local_playback: AudioStreamGeneratorPlayback = null
var local_voice_buffer: PackedByteArray = PackedByteArray()
var network_playback: AudioStreamGeneratorPlayback = null
var network_voice_buffer: PackedByteArray = PackedByteArray()
var packet_read_limit: int = 5

var listening_player_dir := Vector2.ONE
var mouse_locked: bool = false
var look_sensitivity: float = 0.01

func _ready() -> void:
	add_to_group("players")
	set_sample_rate(true)
	prox_local.play()
	local_playback = prox_local.get_stream_playback()
	prox_network.play()
	network_playback = prox_network.get_stream_playback()
	
	if is_multiplayer_authority():
		camera_3d.set_current(true)
		player_name = SteamManager.STEAM_USERNAME
		steam_id = SteamManager.STEAM_ID
		name_label.text = ""
	else:
		steam_id = multiplayer.multiplayer_peer.get_steam64_from_peer_id(get_multiplayer_authority())
		player_name = Steam.getFriendPersonaName(steam_id)
		name_label.text = player_name
	
	var devices := AudioServer.get_input_device_list()
	print("Audio devices:")
	for device in devices:
		print(" ", device)
	print("Current audio device: ", AudioServer.input_device)
	
	if get_window().has_focus():
		_on_window_focus()
	get_window().focus_entered.connect(_on_window_focus)
	
func _process(delta: float) -> void:
	if is_multiplayer_authority():
		check_for_voice()

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		return
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
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
	if Input.is_action_just_pressed("voice_record"):
		record_voice(true)
	elif Input.is_action_just_released("voice_record"):
		record_voice(false)
	
	if event.is_action_pressed("ui_cancel"):
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

func check_for_voice():
	var available_voice := Steam.getAvailableVoice()
	if available_voice["result"] == Steam.VOICE_RESULT_OK and available_voice["buffer"] > 0:
		var voice_data := Steam.getVoice()
		if voice_data["result"] == Steam.VOICE_RESULT_OK and voice_data["written"]:
			print("Voice message has data: %s / %s" % [voice_data['result'], voice_data['written']])
			SteamManager.send_voice_data(voice_data["buffer"])
			
			if has_loopback:
				process_voice_data(voice_data["buffer"], "local")

func set_sample_rate(use_default: bool = false) -> void:
	if use_default:
		current_sample_rate = 48000
	else:
		current_sample_rate = Steam.getVoiceOptimalSampleRate()
	prox_local.stream.mix_rate = current_sample_rate
	prox_network.stream.mix_rate = current_sample_rate
	print("Current sample rate: %s" % current_sample_rate)

func process_voice_data(voice_data: PackedByteArray, voice_source: String):
	set_sample_rate(true)
	var decompressed_voice := Steam.decompressVoice(voice_data, current_sample_rate)
	if decompressed_voice["result"] == Steam.VOICE_RESULT_OK and decompressed_voice["size"] > 0:
		if voice_source == "local":
			local_voice_buffer = decompressed_voice["uncompressed"]
			local_voice_buffer.resize(decompressed_voice["size"])
			_process_voice_data_buffer(local_voice_buffer, local_playback)
		elif voice_source == "network":
			network_voice_buffer = decompressed_voice["uncompressed"]
			network_voice_buffer.resize(decompressed_voice["size"])
			_process_voice_data_buffer(network_voice_buffer, network_playback)

func _process_voice_data_buffer(buffer: PackedByteArray, playback: AudioStreamGeneratorPlayback):
	while playback.get_frames_available() > 0 and buffer.size() > 0:
		# Steam's audio data is represented as 16-bit single channel PCM audio, so we need to convert it to amplitudes
		# Combine the low and high bits to get full 16-bit value
		var raw_value: int = buffer[0] | (buffer[1] << 8)
		# Make it a 16-bit signed integer
		raw_value = (raw_value + 32768) & 0xffff
		# Convert the 16-bit integer to a float on from -1 to 1
		var amplitude: float = float(raw_value - 32768) / 32768.0

		# push_frame() takes a Vector2. The x represents the left channel and the y represents the right channel
		playback.push_frame(listening_player_dir * amplitude)

		# Delete the used samples
		buffer.remove_at(0)
		buffer.remove_at(0)

func record_voice(is_recording: bool):
	# If talking, suppress all other audio or voice comms from the Steam UI
	Steam.setInGameVoiceSpeaking(SteamManager.STEAM_ID, is_recording)
	if is_recording:
		Steam.startVoiceRecording()
		print("Recording voice")
	else:
		Steam.stopVoiceRecording()
		print("Stopped recording voice")
	
	
