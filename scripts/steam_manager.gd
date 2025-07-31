extends Node

const STEAM_APP_ID: int = 480
var STEAM_USERNAME: String = ""
var STEAM_ID: int = 0

var lobby_id: int = 0
var is_lobby_host: bool = false
var lobby_members: Array

var peer = SteamMultiplayerPeer.new()

const Net = preload("res://scripts/net_p2p.gd")
const Packets = preload('res://scripts/proto/packets.gd')

func _init() -> void:
	OS.set_environment("SteamAppID", str(STEAM_APP_ID))
	OS.set_environment("SteamGameID", str(STEAM_APP_ID))

func _ready() -> void:
	Steam.steamInit()
	
	STEAM_ID = Steam.getSteamID()
	STEAM_USERNAME = Steam.getPersonaName()
	
	print(STEAM_ID, " : ", STEAM_USERNAME)

	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.p2p_session_request.connect(_on_p2p_session_request)

func _process(_delta: float) -> void:
	if lobby_id	> 0:
		read_all_p2p_packets()
	
	Steam.run_callbacks()

func _on_lobby_joined(lobby_id, _permissions, _locked, response):
	print("On joined lobby ", response)
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		var fail_reason = get_chat_room_fail_response(response)
		print("Failed to join lobby: ", fail_reason)
		return
		
	self.lobby_id = lobby_id
	fetch_lobby_members()
	make_p2p_handshake()
	
func _on_p2p_session_request(remote_steam_id):
	Steam.acceptP2PSessionWithUser(remote_steam_id)

func broadcast_lobby(data: PackedByteArray, send_type = 0, channel: int = 0):
	Net.broadcast(lobby_members, data, send_type, channel)

func send_voice_data(data: PackedByteArray):
	var packet = Packets.Packet.new()
	packet.set_type(Packets.PacketType.VOICE)
	var voice_data = Packets.VoiceData.new()
	voice_data.set_voice_data(data)
	packet.set_data(voice_data.to_bytes())
	Net.broadcast(lobby_members, packet.to_bytes())

func read_all_p2p_packets(channel: int = 0, read_count: int = 0):
	if read_count > Net.PACKET_READ_LIMIT:
		return
	if Steam.getAvailableP2PPacketSize(channel) > 0:
		read_p2p_packet(channel)
		read_all_p2p_packets(read_count + 1, channel)

func read_p2p_packet(channel: int = 0):
	var packet_size := Steam.getAvailableP2PPacketSize(channel)
	if packet_size == 0:
		return
	var packet := Steam.readP2PPacket(packet_size, channel)
	var sender_id: int = packet["remote_steam_id"]
	var packet_data := Packets.Packet.new()
	var result_code := packet_data.from_bytes(packet["data"])
	if result_code != Packets.PB_ERR.NO_ERRORS:
		print("Error parsing packet data, code: ", result_code)
		return
		
	print(packet_data.get_type())
	match packet_data.get_type():
		Packets.PacketType.STEAM_ID:
			var info := Packets.SteamInfo.new()
			info.from_bytes(packet_data.get_data())
			print("Player joined:")
			if info.has_steam_id():
				print("ID: ", info.get_steam_id())
			if info.has_steam_username():
				print("User name: ", info.get_steam_username())
			fetch_lobby_members()
		Packets.PacketType.VOICE:
			var voice_data := Packets.VoiceData.new()
			voice_data.from_bytes(packet_data.get_data())
			var sender_player := get_player(sender_id)
			if sender_player == null:
				printerr("[read_p2p_packet] Could not find sending_player when parsing voice packet")
				return
			sender_player.process_voice_data(voice_data.get_voice_data(), "network")

func get_player(steam_id: int) -> Node:
	var players := get_tree().get_nodes_in_group("players")
	for player in players:
		if player.steam_id == steam_id:
			return player
	return null

func make_p2p_handshake():
	var packet := Packets.Packet.new()
	packet.set_type(Packets.PacketType.STEAM_ID)
	var info := Packets.SteamInfo.new()
	info.set_steam_id(STEAM_ID)
	info.set_steam_username(STEAM_USERNAME)
	packet.set_data(info.to_bytes())
	broadcast_lobby(packet.to_bytes())

func fetch_lobby_members() -> Array:
	lobby_members.clear()
	var num_members := Steam.getNumLobbyMembers(lobby_id)
	for member_index in range(0, num_members):
		var member_steam_id := Steam.getLobbyMemberByIndex(lobby_id, member_index)
		lobby_members.append(member_steam_id)
	return lobby_members

func get_chat_room_fail_response(response: Steam.ChatRoomEnterResponse):
	var fail_reason : String = ""
	match response:
		Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST: fail_reason = "This lobby no longer exists."
		Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED: fail_reason = "You don't have permission to join this lobby."
		Steam.CHAT_ROOM_ENTER_RESPONSE_FULL: fail_reason = "The lobby is now full."
		Steam.CHAT_ROOM_ENTER_RESPONSE_ERROR: fail_reason = "Uh... something unexpected happened!"
		Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED: fail_reason = "You are banned from this lobby."
		Steam.CHAT_ROOM_ENTER_RESPONSE_LIMITED: fail_reason = "You cannot join due to having a limited account."
		Steam.CHAT_ROOM_ENTER_RESPONSE_CLAN_DISABLED: fail_reason = "This lobby is locked or disabled."
		Steam.CHAT_ROOM_ENTER_RESPONSE_COMMUNITY_BAN: fail_reason = "This lobby is community locked."
		Steam.CHAT_ROOM_ENTER_RESPONSE_MEMBER_BLOCKED_YOU: fail_reason = "A user in the lobby has blocked you from joining."
		Steam.CHAT_ROOM_ENTER_RESPONSE_YOU_BLOCKED_MEMBER: fail_reason = "A user you have blocked is in the lobby."
	return fail_reason
