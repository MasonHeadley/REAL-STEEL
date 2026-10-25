extends Node
# Playing with other people: the lobby. One player hosts and the rest join, up to ten in all.
#
# What is here: making a lobby (with a name and an optional password), finding lobbies on
# the same network, joining by address, the roster with its two teams, and the leader's
# powers (the crown): kick, hand the crown on, set the game mode and rules for everyone.
# The match itself is in netplay.gd; this hands it the seats and says when to begin.
#
# With Steam running, lobbies are Steam lobbies and the connection goes through Steam's
# relay servers, so it works across the internet with no ports to open: the host opens a
# lobby, friends find it by name under Find Lobbies. (The game borrows Steam's public test
# app, number 480, until it has an app number of its own.) Without Steam, or started with
# --lan, the connection is Godot's own, straight from one PC to another on the same
# network. Either way everything above the connection is the same.
#
# The host's copy of the roster is the real one. Everyone else asks the host for changes
# (ask) and is sent the whole lobby again whenever anything changes (_sync).

signal changed                  # the roster or the settings are different now
signal closed(reason: String)   # we are no longer in a lobby, and why
signal found(lobbies: Array)    # a search finished: [{name, address, players, max, locked}]
signal started                  # the leader started the match

const PORT := 24680        # the lobby itself
const FIND_PORT := 24681   # answers "is there a lobby here?"
const MAX_PLAYERS := 30     # ten seats each for Blue, Red and the spectators
const SEATS := 10           # seats in each column of the lobby's table
const SPECTATOR := 2        # the "team" of someone who is only watching
const HAIL := "STEELPUSH?"
const STEAM_APP := 480           # Steam's public test app ("Spacewar"), until this game has its own number
const STEAM_TAG := "steelpush"   # marks our lobbies among everyone else's on the test app

var active := false
var members := {}      # peer id -> {"name": String, "team": 0 (Blue), 1 (Red) or 2 (spectator), "seat": 0..9}
var bots := {}         # "team:seat" -> true, for each seat the leader has put a bot in
var watchers: Array = []  # in a match: the peer ids of those spectating
var leader := 1        # who wears the crown
var lobby_name := ""
var locked := false    # needs a password
var settings := {}     # {"mode": id, "rules": {...}}, chosen by the leader
var my_name := "Player"
var _password := ""
var _joining_with := ""
var _beacon: PacketPeerUDP
var _probe: PacketPeerUDP
var _probe_t := 0.0
var _seen := {}
var steam = null         # the Steam plugin, if it is there
var steam_ok := false    # Steam is running and signed in
var steam_lobby := 0     # the Steam lobby we are in
var in_match := false    # a networked match is being played (or about to be)
var seats: Array = []    # who sits where in it: [{id, team, index, peer, name}], peer 0 for a bot
var match_seed := 0      # so every PC makes the same random choices setting the match up
var _hosting: Array = [] # the name and password of a Steam lobby being created


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	my_name = Settings.player_name
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.connected_to_server.connect(func(): _hello.rpc_id(1, my_name, _joining_with))
	multiplayer.connection_failed.connect(func(): _close("Could not reach that lobby."))
	multiplayer.server_disconnected.connect(func(): _close("The host closed the lobby."))
	var testing := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nettest="):
			testing = true
			_self_test(a.trim_prefix("--nettest="))
	if not testing and not OS.get_cmdline_user_args().has("--lan") and DisplayServer.get_name() != "headless" and Engine.has_singleton("Steam"):
		_start_steam()
	if OS.get_cmdline_user_args().has("--steamtest"):
		# Checks the Steam side on its own: sign-in, opening a lobby, and the lobby list.
		print("STEAMTEST ok=%s named=%s" % [steam_ok, my_name != ""])
		await get_tree().create_timer(2.0).timeout
		found.connect(func(list): print("STEAMTEST list has %d of our lobbies" % list.size()))
		closed.connect(func(reason): print("STEAMTEST closed - ", reason))
		print("STEAMTEST host -> '%s'" % host("Steam test lobby", ""))
		await get_tree().create_timer(4.0).timeout
		print("STEAMTEST active=%s in_steam_lobby=%s members=%d server=%s peer=%s" % [active, steam_lobby != 0, members.size(), multiplayer.is_server(), multiplayer.multiplayer_peer.get_class()])
		search()
		await get_tree().create_timer(4.0).timeout
		leave()
		get_tree().quit()


func _start_steam() -> void:
	steam = Engine.get_singleton("Steam")
	OS.set_environment("SteamAppId", str(STEAM_APP))
	OS.set_environment("SteamGameId", str(STEAM_APP))
	var result: Dictionary = steam.steamInitEx(STEAM_APP, true)
	steam_ok = int(result.get("status", 1)) == 0
	if not steam_ok:
		return
	steam.lobby_created.connect(_on_steam_lobby_created)
	steam.lobby_joined.connect(_on_steam_lobby_joined)
	steam.lobby_match_list.connect(_on_steam_lobby_list)
	steam.join_requested.connect(func(lobby: int, _friend: int): join("steam:%d" % lobby, ""))
	if my_name == "":
		my_name = String(steam.getPersonaName()).left(20)


func _on_steam_lobby_created(result: int, lobby: int) -> void:
	if result != 1:
		_close("Steam could not open a lobby.")
		return
	steam_lobby = lobby
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	peer.host_with_lobby(lobby)
	multiplayer.multiplayer_peer = peer
	_become_host(_hosting[0], _hosting[1])
	steam.setLobbyData(lobby, "game", STEAM_TAG)
	steam.setLobbyData(lobby, "name", lobby_name)
	steam.setLobbyData(lobby, "locked", "1" if locked else "0")
	steam.setLobbyJoinable(lobby, true)


func _on_steam_lobby_joined(lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		_close("Could not join that lobby.")
		return
	if steam.getLobbyOwner(lobby) == steam.getSteamID():
		return  # it is our own lobby, just made
	steam_lobby = lobby
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	peer.connect_to_lobby(lobby)
	multiplayer.multiplayer_peer = peer


func _on_steam_lobby_list(lobbies: Array) -> void:
	var list: Array = []
	for lobby in lobbies:
		list.append({"name": steam.getLobbyData(lobby, "name"), "players": steam.getNumLobbyMembers(lobby), "max": MAX_PLAYERS,
			"locked": steam.getLobbyData(lobby, "locked") == "1", "address": "steam:%d" % lobby})
	found.emit(list)


func my_id() -> int:
	return multiplayer.get_unique_id()


func is_leader() -> bool:
	return active and my_id() == leader


func set_my_name(text: String) -> void:
	my_name = text.strip_edges().left(20)
	Settings.player_name = my_name
	Settings.save()


# Opens a lobby on this PC. Returns "" if it worked, or what went wrong.
func host(title: String, password: String) -> String:
	leave()
	if steam_ok:
		# Steam answers in a moment (_on_steam_lobby_created), and the lobby opens then.
		_hosting = [title, password]
		steam.createLobby(2, MAX_PLAYERS)  # 2 = public: anyone can find it by name
		return ""
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 16) != OK:
		return "Could not open a lobby. Is one already open on this PC?"
	multiplayer.multiplayer_peer = peer
	_beacon = PacketPeerUDP.new()
	_beacon.bind(FIND_PORT)
	_become_host(title, password)
	return ""


func _become_host(title: String, password: String) -> void:
	active = true
	leader = 1
	if my_name == "":
		my_name = "Player"
	lobby_name = title.strip_edges().left(30) if title.strip_edges() != "" else my_name + "'s lobby"
	_password = password
	locked = password != ""
	members = {1: {"name": my_name, "team": 0, "seat": 0}}
	bots = {}
	settings = {"mode": Settings.mode_id, "rules": Settings.rules.duplicate(true)}
	changed.emit()


# Starts joining the lobby at an address. The answer comes later: `changed` once we are in,
# or `closed` with the reason if we were turned away.
func join(address: String, password: String) -> String:
	leave()
	if my_name == "":
		my_name = "Player"
	if address.begins_with("steam:"):
		if not steam_ok:
			return "Steam is not running."
		_joining_with = password
		steam.joinLobby(int(address.trim_prefix("steam:")))
		return ""
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address.strip_edges(), PORT) != OK:
		return "That does not look like an address."
	if my_name == "":
		my_name = "Player"
	_joining_with = password
	multiplayer.multiplayer_peer = peer
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _beacon != null:
		_beacon.close()
		_beacon = null
	if steam_lobby != 0 and steam_ok:
		steam.leaveLobby(steam_lobby)
	steam_lobby = 0
	in_match = false
	active = false
	bots = {}
	members = {}
	settings = {}


func _close(reason: String) -> void:
	leave()
	closed.emit(reason)


# ---- changes, all decided by the host ----

# what: "sit" ([team, seat]) to move to an empty seat; and for the leader only "bot"
# ([team, seat]: puts a bot in an empty seat, or takes one out), "fill" (bots up to five a
# side), "clear" (no bots), "kick" (id), "crown" (id), "settings" (dictionary), "start".
func ask(what: String, arg = null) -> void:
	if not active:
		return
	if multiplayer.is_server():
		_handle(1, what, arg)
	else:
		_ask.rpc_id(1, what, arg)


@rpc("any_peer", "call_remote", "reliable")
func _ask(what: String, arg) -> void:
	if multiplayer.is_server():
		_handle(multiplayer.get_remote_sender_id(), what, arg)


func _handle(from: int, what: String, arg) -> void:
	if not members.has(from):
		return
	if what == "sit":
		if arg is Array and arg.size() == 2 and seat_free(int(arg[0]), int(arg[1])):
			members[from]["team"] = int(arg[0])
			members[from]["seat"] = int(arg[1])
	elif from != leader:
		return
	elif what == "bot" and arg is Array and arg.size() == 2 and int(arg[0]) != SPECTATOR:
		var key := "%d:%d" % [int(arg[0]), int(arg[1])]
		if bots.has(key):
			bots.erase(key)
		elif seat_free(int(arg[0]), int(arg[1])):
			bots[key] = true
	elif what == "fill":
		for team in 2:
			for seat in SEATS:
				if _team_count(team) < 5 and seat_free(team, seat):
					bots["%d:%d" % [team, seat]] = true
	elif what == "clear":
		bots = {}
	elif what == "kick" and members.has(int(arg)) and int(arg) != 1:
		_turn_away(int(arg), "The host removed you from the lobby.")
		members.erase(int(arg))
	elif what == "crown" and members.has(int(arg)):
		leader = int(arg)
	elif what == "settings" and arg is Dictionary:
		settings = arg
	elif what == "start":
		# The match has exactly who the table shows: each team's players and bots, in seat
		# order. Nothing is filled in. Spectators get no vehicle.
		var table: Array = []
		for team in 2:
			var index := 0
			for seat in SEATS:
				var peer := who_sits(team, seat)
				if peer == 0 and not bots.has("%d:%d" % [team, seat]):
					continue
				table.append({"id": table.size(), "team": team, "index": index, "peer": maxi(peer, 0), "name": members[peer]["name"] if peer > 0 else ""})
				index += 1
		var chosen := randi()
		_go.rpc(table, chosen, settings)
		_begin(table, chosen, settings)
		return
	_send_lobby()


# How many players and bots a team has.
func _team_count(team: int) -> int:
	var n := 0
	for id in members:
		if members[id]["team"] == team:
			n += 1
	for key in bots:
		if String(key).begins_with("%d:" % team):
			n += 1
	return n


# Who is in a seat: a player's peer id, -1 for a bot, 0 for nobody.
func who_sits(team: int, seat: int) -> int:
	for id in members:
		if members[id]["team"] == team and int(members[id].get("seat", 0)) == seat:
			return id
	return -1 if bots.has("%d:%d" % [team, seat]) else 0


func seat_free(team: int, seat: int) -> bool:
	return team >= 0 and team <= SPECTATOR and seat >= 0 and seat < SEATS and who_sits(team, seat) == 0


# Somewhere for a newcomer to sit: the emptier team if it has room, else with the spectators.
func _first_free_seat() -> Array:
	var order: Array = [0, 1] if _team_count(0) <= _team_count(1) else [1, 0]
	for team in order + [SPECTATOR]:
		for seat in SEATS:
			if seat_free(team, seat):
				return [team, seat]
	return [SPECTATOR, 0]


@rpc("any_peer", "call_remote", "reliable")
func _hello(their_name: String, password: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_match:
		_turn_away(id, "A match is being played. Try again when it ends.")
	elif locked and password != _password:
		_turn_away(id, "Wrong password.")
	elif members.size() >= MAX_PLAYERS:
		_turn_away(id, "That lobby is full.")
	else:
		var place := _first_free_seat()
		members[id] = {"name": their_name.strip_edges().left(20), "team": place[0], "seat": place[1]}
		_send_lobby()


func _turn_away(id: int, reason: String) -> void:
	_refused.rpc_id(id, reason)
	# Give the message a moment to arrive before hanging up.
	get_tree().create_timer(0.5).timeout.connect(func():
		if multiplayer.is_server() and multiplayer.get_peers().has(id):
			multiplayer.multiplayer_peer.disconnect_peer(id))


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	_close(reason)


func _send_lobby() -> void:
	for id in members:
		if id != 1:
			_sync.rpc_id(id, members, leader, lobby_name, locked, settings, bots)
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync(p_members: Dictionary, p_leader: int, p_name: String, p_locked: bool, p_settings: Dictionary, p_bots: Dictionary) -> void:
	members = p_members
	bots = p_bots
	leader = p_leader
	lobby_name = p_name
	locked = p_locked
	settings = p_settings
	active = true
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _go(table: Array, chosen: int, with: Dictionary) -> void:
	_begin(table, chosen, with)


# The match is on: note who sits where, take the host's mode and rules for it (in memory
# only; nothing is saved over the player's own), and let the game know.
func _begin(table: Array, chosen: int, with: Dictionary) -> void:
	seats = table
	watchers = members.keys().filter(func(id): return members[id]["team"] == SPECTATOR)
	match_seed = chosen
	settings = with
	in_match = true
	if GameData.modes.has(String(with.get("mode", ""))):
		Settings.mode_id = with["mode"]
	for key in with.get("rules", {}):
		Settings.rules[key] = with["rules"][key]
	started.emit()


func _on_peer_gone(id: int) -> void:
	if multiplayer.is_server() and members.has(id):
		members.erase(id)
		if leader == id:
			leader = 1  # the crown comes back to the PC that is running the lobby
		_send_lobby()


# ---- finding lobbies on the same network ----

# Calls out on the local network and gathers the answers for a second, then emits `found`.
func search() -> void:
	if steam_ok:
		steam.addRequestLobbyListStringFilter("game", STEAM_TAG, 0)  # 0 = must be equal
		steam.addRequestLobbyListDistanceFilter(3)                   # 3 = anywhere in the world
		steam.requestLobbyList()
		return
	_probe = PacketPeerUDP.new()
	_probe.set_broadcast_enabled(true)
	_seen = {}
	for address in ["255.255.255.255", "127.0.0.1"]:
		_probe.set_dest_address(address, FIND_PORT)
		_probe.put_packet(HAIL.to_utf8_buffer())
	_probe_t = 1.0


func _process(delta: float) -> void:
	# A host answers anyone asking whether there is a lobby here.
	while _beacon != null and _beacon.get_available_packet_count() > 0:
		var asked := _beacon.get_packet().get_string_from_utf8()
		if asked == HAIL:
			_beacon.set_dest_address(_beacon.get_packet_ip(), _beacon.get_packet_port())
			_beacon.put_packet(JSON.stringify({"name": lobby_name, "players": members.size(), "max": MAX_PLAYERS, "locked": locked}).to_utf8_buffer())
	if _probe == null:
		return
	while _probe.get_available_packet_count() > 0:
		var answer = JSON.parse_string(_probe.get_packet().get_string_from_utf8())
		if answer is Dictionary and answer.has("name"):
			answer["address"] = _probe.get_packet_ip()
			_seen[String(answer["name"])] = answer  # one PC can answer twice (broadcast and loopback)
	_probe_t -= delta
	if _probe_t <= 0.0:
		_probe.close()
		_probe = null
		found.emit(_seen.values())


# ---- checking it works: two copies of the game on one PC ----
#   --nettest=host   opens a locked lobby, reports who is in it, kicks the last to join
#   --nettest=join   finds it, is refused with a wrong password, gets in with the right one
#   --nettest=extra  joins a little later, to be the one who is kicked
func _self_test(part: String) -> void:
	var say := func(text: String): print("NETTEST %s: %s" % [part, text])
	var roster := func() -> String:
		var names: Array = []
		for id in members:
			names.append("%s%s(team %d)" % ["*" if id == leader else "", members[id]["name"], members[id]["team"]])
		return ", ".join(names)
	closed.connect(func(reason): say.call("closed - " + reason))
	found.connect(func(list): say.call("found %s" % [list.map(func(l): return "%s %d/%d locked=%s" % [l["name"], l["players"], l["max"], l["locked"]])]))
	my_name = part.capitalize()
	await get_tree().create_timer(0.5).timeout
	if part == "host":
		say.call("host -> '%s'" % host("Test lobby", "secret"))
		await get_tree().create_timer(9.0).timeout
		say.call("roster " + roster.call())
		var last: int = members.keys().max()
		ask("kick", last)
		ask("crown", members.keys().filter(func(id): return id != 1 and id != last).front())
		await get_tree().create_timer(2.0).timeout
		say.call("after kick and crown: " + roster.call())
		await get_tree().create_timer(3.0).timeout
	elif part == "join":
		await get_tree().create_timer(1.0).timeout
		search()
		await found
		join("127.0.0.1", "wrong")
		await closed
		join("127.0.0.1", "secret")
		await changed
		say.call("in: " + roster.call())
		ask("sit", [0, 3])
		await get_tree().create_timer(9.0).timeout
		say.call("leader=%s roster %s" % [is_leader(), roster.call()])
		ask("settings", {"mode": "deathmatch", "rules": {}})
		await get_tree().create_timer(1.0).timeout
		say.call("settings now %s" % [settings.get("mode", "?")])
	elif part == "hostmatch" or part == "joinmatch":
		# A whole networked match between two copies: one hosts and starts it, the other
		# joins, picks a vehicle and holds the trigger. Both report what they end up seeing.
		if part == "hostmatch":
			say.call("host -> '%s'" % host("Match test", ""))
			while members.size() < 2:
				await get_tree().create_timer(0.3).timeout
			for seat in range(1, 5):
				ask("bot", [0, seat])
				ask("bot", [1, seat])
			ask("start")
		else:
			await get_tree().create_timer(1.5).timeout
			join("127.0.0.1", "")
			await started
		await get_tree().create_timer(2.0).timeout
		var game = get_tree().current_scene
		game.prep_t = minf(game.prep_t, 1.0) if multiplayer.is_server() else game.prep_t
		for moment in 9:
			await get_tree().create_timer(4.0).timeout
			game = get_tree().current_scene
			var mine = game.player_slot.get("tank")
			if mine != null and is_instance_valid(mine):
				game.player_ctrl.set_physics_process(false)  # nobody is at the keyboard: hold the controls for it
				mine.throttle = 1.0
				mine.want_fire = true
			elif not game.player_slot.get("ready", false):
				# Deploy exactly as the deploy screen's button does, wait and all.
				# (--netpick=air:apache or inf:medic has this copy fly or go on foot instead.)
				var pick := "bastion"
				for arg in OS.get_cmdline_user_args():
					if arg.begins_with("--netpick="):
						pick = arg.trim_prefix("--netpick=")
				game.spawn_screen.selected = pick
				game.spawn_screen._deploy()
			var where := "no vehicle" if mine == null or not is_instance_valid(mine) else "at %s hp %d" % [mine.global_position.snapped(Vector3.ONE), int(mine.hp)]
			where += "  aircraft %d" % game.aircraft.size()
			if game.player_air != null and is_instance_valid(game.player_air):
				where += "  flying %s at %s hp %d" % [game.player_air.def["id"], game.player_air.global_position.snapped(Vector3.ONE), int(game.player_air.hp)]
			if game.player_man != null and is_instance_valid(game.player_man):
				where += "  on foot at %s (%s)" % [game.player_man.global_position.snapped(Vector3.ONE), game.player_man.state]
			var shifted := 0
			for p in game.map.props:
				shifted += 1 if is_instance_valid(p) and p.position.distance_to(p.get_meta("start", p.position)) > 0.5 else 0
				if not p.has_meta("start"):
					p.set_meta("start", p.position)
			say.call("t=%d client=%s vehicles=%d mine=%s kills=%s time=%d soldiers=%d props_moved=%d" % [moment * 4, game.net_client, game.tanks.size(), where, game.team_kills, int(game.time_left), game.soldiers.size() + game.downed.size(), shifted])
	else:
		await get_tree().create_timer(5.0).timeout
		join("127.0.0.1", "secret")
		await closed
	get_tree().quit()
