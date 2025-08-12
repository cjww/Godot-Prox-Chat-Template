extends AudioStreamPlayer3D

@export_range(0, 20) var audio_amplification: float = 5.0

const Net = preload("res://scripts/net_p2p.gd")

var current_sample_rate: int = 48000
var has_loopback: bool = false
var playback: AudioStreamGeneratorPlayback = null
var voice_buffer: PackedByteArray = PackedByteArray()
var packet_read_limit: int = 5

func _ready() -> void:
	add_to_group("players")
	set_sample_rate(true)
	play()
	playback = get_stream_playback()
	
func _process(delta: float) -> void:
	if is_multiplayer_authority():
		_check_for_voice()

func _input(event: InputEvent) -> void:
	if !is_multiplayer_authority():
		return
	if Input.is_action_just_pressed("VoiceRecord"):
		record_voice(true)
	elif Input.is_action_just_released("VoiceRecord"):
		record_voice(false)
			
func _check_for_voice():
	var available_voice := Steam.getAvailableVoice()
	if available_voice["result"] == Steam.VOICE_RESULT_OK and available_voice["buffer"] > 0:
		var voice_data := Steam.getVoice()
		if voice_data["result"] == Steam.VOICE_RESULT_OK and voice_data["written"]:
			print("Voice message has data: %s / %s" % [voice_data['result'], voice_data['written']])
			SteamManager.send_voice_data(voice_data["buffer"])
			if has_loopback:
				process_voice_data(voice_data["buffer"])

func set_sample_rate(use_default: bool = false) -> void:
	if use_default:
		current_sample_rate = 48000
	else:
		current_sample_rate = Steam.getVoiceOptimalSampleRate()
	stream.mix_rate = current_sample_rate
	print("Current sample rate: %s" % current_sample_rate)

func process_voice_data(voice_data: PackedByteArray):
	set_sample_rate(true)
	var decompressed_voice := Steam.decompressVoice(voice_data, current_sample_rate)
	if decompressed_voice["result"] == Steam.VOICE_RESULT_OK and decompressed_voice["size"] > 0:
		voice_buffer = decompressed_voice["uncompressed"]
		voice_buffer.resize(decompressed_voice["size"])
		_process_voice_data_buffer(voice_buffer, playback)

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
		playback.push_frame(Vector2.ONE * amplitude * audio_amplification)

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
	
	
