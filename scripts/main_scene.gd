extends Node3D

@onready var lobbies_list: VBoxContainer = $LobbyUI/VBoxContainer/ScrollContainer/LobbiesList
@onready var lobby_ui: Control = $LobbyUI
@onready var player_spawner: MultiplayerSpawner = $Players/PlayerSpawner

var lobby_id: int = 0
var was_lobby_created: bool = false

var peer = SteamMultiplayerPeer

func _ready() -> void:
	peer = SteamManager.peer
	peer.lobby_created.connect(_on_lobby_created)
	
	Steam.lobby_match_list.connect(_on_lobby_match)

func _on_host_btn_pressed() -> void:
	if was_lobby_created:
		return
	var err = peer.create_lobby(SteamMultiplayerPeer.LOBBY_TYPE_PUBLIC)
	if err != OK:
		printerr("Error hosting: ", err)
		return
	multiplayer.multiplayer_peer = peer

func _on_join_btn_pressed() -> void:
	refresh_lobby_list()
	
func refresh_lobby_list() -> void:
	var lobbies_buttons = lobbies_list.get_children()
	for btn in lobbies_buttons:
		btn.queue_free()
	open_lobby_list()

func open_lobby_list():
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()

func _on_lobby_match(lobbies: Array):
	if lobbies.is_empty():
		print("No lobbies found")
		return
		
	for lobby in lobbies:
		var lobby_name := Steam.getLobbyData(lobby, "name")
		var members := Steam.getNumLobbyMembers(lobby)
		var member_limit := Steam.getLobbyMemberLimit(lobby)
		
		var btn := Button.new()
		btn.set_text("{0} | {1}/{2}".format([lobby_name, members, member_limit]))
		btn.set_size(Vector2(400, 50))
		btn.pressed.connect(join_lobby.bind(lobby))
		lobbies_list.add_child(btn)

func join_lobby(lobby_id: int):
	peer.connect_lobby(lobby_id)
	multiplayer.multiplayer_peer = peer
	self.lobby_id = lobby_id	
	SteamManager.lobby_id = lobby_id
	print("Joined lobby ", Steam.getLobbyData(lobby_id, "name"))
	enable_ui(false)

func _on_lobby_created(result, lobby_id) -> void:
	if result != Steam.Result.RESULT_OK:
		printerr("[_on_lobby_created] Failed to create lobby ", result)
		return
	
	self.lobby_id = lobby_id
	Steam.setLobbyData(lobby_id, "name", str(SteamManager.STEAM_USERNAME))
	Steam.setLobbyJoinable(lobby_id, true)
	SteamManager.lobby_id = lobby_id
	SteamManager.is_lobby_host = true
	enable_ui(false)
	player_spawner.spawn_host()
	print("[_on_lobby_created] Created lobby!")


func enable_ui(value):
	lobby_ui	.visible = value
