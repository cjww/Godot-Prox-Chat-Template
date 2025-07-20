extends Node

var STEAM_APP_ID: int = 480
var STEAM_USERNAME: String = ""
var STEAM_ID: int = 0

var lobby_id: int = 0
var is_lobby_host: bool = false

var peer = SteamMultiplayerPeer.new()

func _init() -> void:
	OS.set_environment("SteamAppID", str(STEAM_APP_ID))
	OS.set_environment("SteamGameID", str(STEAM_APP_ID))

func _ready() -> void:
	Steam.steamInit()
	
	STEAM_ID = Steam.getSteamID()
	STEAM_USERNAME = Steam.getPersonaName()
	
	print(STEAM_ID, " : ", STEAM_USERNAME)

func _process(delta: float) -> void:
	Steam.run_callbacks()
