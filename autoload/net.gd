# =============================================================
# net.gd — AUTOLOAD "Net"  ★ WHO IS PLAYING, AND WHO DECIDES ★
# -------------------------------------------------------------
# Same-house co-op over the local network. One machine hosts and
# owns the world; everyone else connects to it.
#
# THE ONE RULE, and everything here follows from it:
#
#   The HOST owns the world. Every player owns their own pockets.
#
#   Shared, host-authoritative . plots, gathered pickups, placed
#                                buildings, who owns which homestead
#   Private, never sent anywhere . coins, seeds, basket, pouch,
#                                  hunger, quests, what you crafted
#
# That split is why this was a day's work and not a rewrite. A
# client never changes shared state directly -- it asks the host,
# the host decides, and the host tells everybody. A client changes
# its own pockets freely, because nobody else can see them.
#
# WHY NOT PEER-TO-PEER: with four kids, "whose version of the farm
# is real" has to have one answer. The host's. See docs/MULTIPLAYER.md.
#
# WHY NO BROWSER SUPPORT: ENet is UDP, which a browser cannot open.
# The web export still works, it just runs single-player.
# =============================================================
extends Node

signal mode_changed()                       # solo / hosting / joined
signal roster_changed()                     # someone arrived or left
signal connection_failed(reason: String)
signal hosts_found()                        # the LAN scan turned something up
signal remote_moved(id: int, pos: Vector3, yaw: float, hop: bool)
signal remote_left(id: int)

enum Mode { SOLO, HOST, CLIENT }

const PORT := 27015
const DISCOVERY_PORT := 27016
const MAX_PLAYERS := 8
const BEACON_SECONDS := 1.0
const HOST_FORGET_SECONDS := 4.0    # drop a host from the list if it goes quiet
const MOVE_HZ := 15.0               # position updates per second

var mode: int = Mode.SOLO
var player_name: String = ""
## peer id -> {"name": String, "homestead": int}
var roster: Dictionary = {}
## Hosts seen on this network: "ip:port" -> {"name", "ip", "players", "last_seen"}
var found_hosts: Dictionary = {}

var _beacon: PacketPeerUDP            # host: shouts "I am here" once a second
var _listener: PacketPeerUDP          # client: listens for those shouts
var _beacon_accum: float = 0.0
var _move_accum: float = 0.0
var _last_sent_pos: Vector3 = Vector3.INF
var _last_sent_yaw: float = 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_host_vanished)
	set_process(true)


func is_solo() -> bool:   return mode == Mode.SOLO
func is_host() -> bool:   return mode == Mode.HOST
func is_client() -> bool: return mode == Mode.CLIENT

## True when this machine decides things: solo play, or hosting.
## Almost every "should I just do it, or ask?" test is this one.
func has_authority() -> bool:
	return mode != Mode.CLIENT


func my_id() -> int:
	return 1 if mode != Mode.CLIENT else multiplayer.get_unique_id()


func player_count() -> int:
	return maxi(1, roster.size())


# =============================================================
#  Starting and stopping
# =============================================================
func host_game(display_name: String) -> bool:
	leave()
	player_name = display_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		# Almost always "something else is already on this port",
		# which in practice means a second copy of the game.
		connection_failed.emit(
			"Could not open the game to the network (error %d). Is Tendril Hills already hosting on this machine?" % err)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	roster = {1: {"name": player_name, "homestead": -1}}
	_start_beacon()
	mode_changed.emit()
	roster_changed.emit()
	return true


func join_game(ip: String, display_name: String) -> bool:
	leave()
	player_name = display_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		connection_failed.emit("Could not reach %s (error %d)." % [ip, err])
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	mode_changed.emit()
	return true


## Back to single player. Safe to call when already solo.
func leave() -> void:
	_stop_beacon()
	if multiplayer.multiplayer_peer != null \
	and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if mode != Mode.SOLO:
		mode = Mode.SOLO
		roster.clear()
		mode_changed.emit()
		roster_changed.emit()


# =============================================================
#  Finding the host without anybody typing an IP address
# -------------------------------------------------------------
# A seven-year-old cannot be asked for 192.168.1.47. So the host
# shouts its name onto the local network once a second, and every
# other copy of the game listens. The join screen is then a list
# of names you click, which is the entire point of this section.
#
# Broadcast does not leave your house -- routers do not forward it
# -- so this is invisible to the internet and needs no ports open.
# =============================================================
func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_beacon_accum = BEACON_SECONDS      # send one immediately


func _stop_beacon() -> void:
	if _beacon:
		_beacon.close()
		_beacon = null


## Start watching for hosts. The join screen calls this; it is
## harmless to call more than once.
func start_scanning() -> void:
	if _listener:
		return
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(DISCOVERY_PORT, "*")
	if err != OK:
		# Usually means this machine is the host and already has the
		# port. That is fine -- a host has no reason to scan.
		_listener = null


func stop_scanning() -> void:
	if _listener:
		_listener.close()
		_listener = null
	found_hosts.clear()


func _process(delta: float) -> void:
	_pump_beacon(delta)
	_pump_listener()


func _pump_beacon(delta: float) -> void:
	if _beacon == null or mode != Mode.HOST:
		return
	_beacon_accum += delta
	if _beacon_accum < BEACON_SECONDS:
		return
	_beacon_accum = 0.0
	var msg := JSON.stringify({
		"game": "tendril-hills",
		"name": player_name,
		"players": roster.size(),
		"max": MAX_PLAYERS,
	})
	_beacon.put_packet(msg.to_utf8_buffer())


func _pump_listener() -> void:
	if _listener == null:
		return
	while _listener.get_available_packet_count() > 0:
		var raw := _listener.get_packet().get_string_from_utf8()
		var ip := _listener.get_packet_ip()
		var parsed: Variant = JSON.parse_string(raw)
		# Anything else on this port is not ours. Ignore it quietly
		# rather than crashing on a stray packet from a printer.
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = parsed
		if String(d.get("game", "")) != "tendril-hills":
			continue
		found_hosts[ip] = {
			"name": String(d.get("name", "Tendril Hills")),
			"ip": ip,
			"players": int(d.get("players", 1)),
			"max": int(d.get("max", MAX_PLAYERS)),
			"last_seen": Time.get_ticks_msec(),
		}
		hosts_found.emit()

	# Forget hosts that have gone quiet, so a laptop that closed the
	# game stops appearing in the list a few seconds later.
	var now := Time.get_ticks_msec()
	var stale: Array = []
	for ip in found_hosts:
		if now - int(found_hosts[ip]["last_seen"]) > int(HOST_FORGET_SECONDS * 1000.0):
			stale.append(ip)
	if not stale.is_empty():
		for ip in stale:
			found_hosts.erase(ip)
		hosts_found.emit()


# =============================================================
#  Arrivals and departures
# =============================================================
func _on_peer_connected(id: int) -> void:
	# Host side only. The newcomer introduces itself in _hello below;
	# until then we know nothing about it but its number.
	if mode != Mode.HOST:
		return


func _on_peer_disconnected(id: int) -> void:
	if roster.has(id):
		roster.erase(id)
		roster_changed.emit()
	remote_left.emit(id)
	if mode == Mode.HOST:
		_push_roster()


func _on_connected() -> void:
	# We are a client and the host accepted us. Introduce ourselves.
	_hello.rpc_id(1, player_name)


func _on_connect_failed() -> void:
	mode = Mode.SOLO
	multiplayer.multiplayer_peer = null
	connection_failed.emit("That machine did not answer. Is Tendril Hills open on it?")
	mode_changed.emit()


func _on_host_vanished() -> void:
	var was_client := mode == Mode.CLIENT
	leave()
	if was_client:
		connection_failed.emit("The host closed the game. You are back in your own world.")


@rpc("any_peer", "call_remote", "reliable")
func _hello(name_in: String) -> void:
	if mode != Mode.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	# Never trust a name off the wire: it goes on a signpost and in
	# the chat line, so it gets trimmed and capped here.
	var clean := name_in.strip_edges().substr(0, 16)
	if clean == "":
		clean = "Sprite %d" % id
	roster[id] = {"name": clean, "homestead": -1}
	roster_changed.emit()
	_push_roster()
	GameState.send_world_to(id)


## Host -> everyone: this is who is here now.
func _push_roster() -> void:
	if mode != Mode.HOST:
		return
	_set_roster.rpc(roster)


@rpc("authority", "call_remote", "reliable")
func _set_roster(r: Dictionary) -> void:
	roster = r
	roster_changed.emit()


# =============================================================
#  Where everybody is standing
# -------------------------------------------------------------
# Positions go out unreliably and at a fixed rate. Unreliable is
# correct here: a dropped position is replaced by the next one 60ms
# later, and resending a stale one would be worse than losing it.
# Only actions that change the world are sent reliably.
# =============================================================
func send_my_position(delta: float, pos: Vector3, yaw: float, hopped: bool) -> void:
	if mode == Mode.SOLO:
		return
	_move_accum += delta
	if not hopped and _move_accum < 1.0 / MOVE_HZ:
		return
	# Standing still costs nothing to send, so do not send it.
	if not hopped \
	and _last_sent_pos.distance_squared_to(pos) < 0.0004 \
	and absf(angle_difference(_last_sent_yaw, yaw)) < 0.02:
		return
	_move_accum = 0.0
	_last_sent_pos = pos
	_last_sent_yaw = yaw
	_moved.rpc(pos, yaw, hopped)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _moved(pos: Vector3, yaw: float, hopped: bool) -> void:
	var from := multiplayer.get_remote_sender_id()
	remote_moved.emit(from, pos, yaw, hopped)
	# The host is the only one everybody is connected to, so it has
	# to pass movement along to the other clients.
	if mode == Mode.HOST:
		for id in roster:
			if int(id) != 1 and int(id) != from:
				_moved_relay.rpc_id(int(id), from, pos, yaw, hopped)


@rpc("authority", "call_remote", "unreliable_ordered")
func _moved_relay(who: int, pos: Vector3, yaw: float, hopped: bool) -> void:
	remote_moved.emit(who, pos, yaw, hopped)


func name_of(id: int) -> String:
	if roster.has(id):
		return String(roster[id]["name"])
	return "Sprite"


# =============================================================
#  Join codes — the way that works on an iPad
# -------------------------------------------------------------
# The beacon above is Mac-only and always will be. iOS requires
# the com.apple.developer.networking.multicast entitlement to send
# OR receive a UDP broadcast, it is a restricted entitlement you
# have to apply to Apple for, and Bonjour browsing for a custom
# service type needs the same one. So an iPad cannot see the
# host list, no matter how it is written.
#
# A join code sidesteps the whole thing. A direct connection to a
# known address is ordinary traffic and is allowed everywhere
# (iOS shows a one-time "allow local network access" prompt).
#
# The trick is that everyone in a house is on the same /24, so
# only the LAST number of the address differs. The host shows
# that number; a guest glues it onto its own subnet. Two or three
# digits, typeable by a seven-year-old, and no entitlement.
#
# When that assumption is wrong -- two subnets, a mesh router
# handing out 10.x to some devices -- the full address still
# works, so the lobby accepts either.
# =============================================================

## This machine's address on the house network, or "" if it is not
## on one. Loopback and link-local are skipped: neither is an
## address anybody else can reach.
func local_ip() -> String:
	var best := ""
	for addr in IP.get_local_addresses():
		var a := String(addr)
		if not _is_ipv4(a):
			continue
		if a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if _is_private(a):
			return a          # a house address; take it immediately
		if best == "":
			best = a
	return best


## The short number to read out. "" if we cannot work one out.
func join_code() -> String:
	var ip := local_ip()
	if ip == "":
		return ""
	return ip.get_slice(".", 3)


## Turn whatever was typed into something to connect to. Accepts a
## full address as-is, or a bare number glued onto our own subnet.
func resolve_code(typed: String) -> String:
	var t := typed.strip_edges()
	if t == "":
		return ""
	if t.count(".") == 3:
		return t                      # they typed the whole thing
	if not t.is_valid_int():
		return ""
	var mine := local_ip()
	if mine == "":
		return ""
	var n := int(t)
	if n < 0 or n > 255:
		return ""
	return "%s.%s.%s.%d" % [mine.get_slice(".", 0), mine.get_slice(".", 1),
		mine.get_slice(".", 2), n]


static func _is_ipv4(a: String) -> bool:
	return a.count(".") == 3 and not a.contains(":")


## The three ranges routers hand out at home.
static func _is_private(a: String) -> bool:
	if a.begins_with("192.168.") or a.begins_with("10."):
		return true
	if a.begins_with("172."):
		var second := int(a.get_slice(".", 1))
		return second >= 16 and second <= 31
	return false
