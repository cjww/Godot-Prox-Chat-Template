extends MultiplayerSpawner

@export var player_scene: PackedScene

var players = {}

func _ready() -> void:
	spawn_function = spawn_player
	print("is authority: ", is_multiplayer_authority())
	if is_multiplayer_authority():
		multiplayer.peer_connected.connect(spawn)
		multiplayer.peer_disconnected.connect(remove_player)

func spawn_host():
	print("[spawn host] is authority: ", is_multiplayer_authority())
	if is_multiplayer_authority():
		spawn(1)

func spawn_player(id):
	var player = player_scene.instantiate()
	player.set_multiplayer_authority(id)
	players[id] = player
	return player

func remove_player(id):
	players[id].queue_free()
	players.erase(id)
