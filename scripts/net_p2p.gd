extends Object

const PACKET_READ_LIMIT: int = 32

static func broadcast(targets: Array, data: PackedByteArray, send_type = 2, channel: int = 0):
	for target in targets:
		Steam.sendP2PPacket(target, data, send_type, channel)
