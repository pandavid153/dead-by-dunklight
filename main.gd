extends Node2D

const SCREEN := Vector2(1280, 720)
const WORLD := Rect2(42, 76, 1196, 580)
const INK := Color("#0c1115")
const PAPER := Color("#e9dec4")
const MIST := Color("#91a8a0")
const RUST := Color("#bc4b38")
const AMBER := Color("#e7a84d")
const MOSS := Color("#627d69")
const BLOOD := Color("#a82f32")

var rng := RandomNumberGenerator.new()
var state := "menu"
var role := "survivor"
var player := Vector2(350, 480)
var hunter := Vector2(980, 218)
var player_health := 2
var hunter_stamina := 100.0
var repairs := [0.0, 0.0, 0.0]
var generators := [Vector2(234, 192), Vector2(640, 312), Vector2(1056, 520)]
var exit_pos := Vector2(1140, 130)
var obstacles := []
var crows := []
var motes := []
var time_alive := 0.0
var alert := 0.0
var attack_flash := 0.0
var damage_flash := 0.0
var swing_cooldown := 0.0
var repair_pulse := 0.0
var objective_pop := 0.0
var hunter_path_timer := 0.0
var hunter_wander := Vector2.ZERO
var message := ""
var message_time := 0.0
var game_result := ""
var camera_shake := 0.0
var font: Font

func _ready() -> void:
	rng.seed = 817334
	font = ThemeDB.fallback_font
	obstacles = [
		Rect2(114, 308, 196, 34), Rect2(424, 130, 38, 158), Rect2(744, 166, 170, 35),
		Rect2(836, 394, 44, 165), Rect2(400, 526, 220, 35), Rect2(98, 564, 125, 32),
		Rect2(1010, 285, 150, 34), Rect2(575, 355, 50, 95)
	]
	for i in 36:
		motes.append({"p": Vector2(rng.randi_range(40, 1240), rng.randi_range(75, 655)), "s": rng.randf_range(6.0, 20.0), "a": rng.randf_range(0.08, 0.35)})
	for i in 13:
		crows.append(Vector2(rng.randi_range(70, 1210), rng.randi_range(95, 630)))
	queue_redraw()

func start_game(chosen_role: String) -> void:
	role = chosen_role
	state = "playing"
	player = Vector2(310, 485) if role == "survivor" else Vector2(980, 218)
	hunter = Vector2(980, 218) if role == "survivor" else Vector2(310, 485)
	player_health = 2
	hunter_stamina = 100.0
	repairs = [0.0, 0.0, 0.0]
	time_alive = 0.0
	game_result = ""
	message = "RESTORE THREE RELAYS"
	message_time = 2.5
	queue_redraw()

func _process(delta: float) -> void:
	if state == "playing":
		time_alive += delta
		message_time = maxf(0.0, message_time - delta)
		alert = maxf(0.0, alert - delta)
		attack_flash = maxf(0.0, attack_flash - delta)
		damage_flash = maxf(0.0, damage_flash - delta)
		swing_cooldown = maxf(0.0, swing_cooldown - delta)
		repair_pulse = maxf(0.0, repair_pulse - delta)
		objective_pop = maxf(0.0, objective_pop - delta)
		camera_shake = maxf(0.0, camera_shake - delta * 2.5)
		if role == "survivor":
			update_survivor(delta)
			update_hunter_ai(delta)
		else:
			update_hunter_player(delta)
			update_survivor_ai(delta)
	for mote in motes:
		mote.p.y -= mote.s * delta
		mote.p.x += sin(Time.get_ticks_msec() * 0.0004 + mote.p.y) * delta * 4.0
		if mote.p.y < WORLD.position.y: mote.p.y = WORLD.end.y
	queue_redraw()

func movement_input() -> Vector2:
	return Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()

func interacting() -> bool:
	return Input.is_key_pressed(KEY_E)

func attacking() -> bool:
	return Input.is_key_pressed(KEY_SPACE)

func move_body(pos: Vector2, motion: Vector2, radius: float) -> Vector2:
	var candidate := pos + motion
	candidate.x = clampf(candidate.x, WORLD.position.x + radius, WORLD.end.x - radius)
	candidate.y = clampf(candidate.y, WORLD.position.y + radius, WORLD.end.y - radius)
	for rect in obstacles:
		if rect.grow(radius).has_point(candidate):
			var x_try := Vector2(candidate.x, pos.y)
			var y_try := Vector2(pos.x, candidate.y)
			if not rect.grow(radius).has_point(x_try): candidate = x_try
			elif not rect.grow(radius).has_point(y_try): candidate = y_try
			else: candidate = pos
	return candidate

func update_survivor(delta: float) -> void:
	var moving := movement_input()
	var speed := 182.0 if alert <= 0.0 else 137.0
	player = move_body(player, moving * speed * delta, 13.0)
	var nearby := nearest_generator(player)
	if nearby >= 0 and player.distance_to(generators[nearby]) < 54.0 and repairs[nearby] < 100.0:
		if interacting():
			repairs[nearby] = minf(100.0, repairs[nearby] + 18.5 * delta)
			repair_pulse = 0.16
			if repairs[nearby] >= 100.0:
				objective_pop = 1.0
				message = "RELAY STABILIZED"
				message_time = 2.0
				for crow in crows: crow += (crow - generators[nearby]).normalized() * 48.0
	if repaired_count() == 3 and player.distance_to(exit_pos) < 46.0 and interacting():
		finish("YOU ESCAPED THE DARK")
	if player.distance_to(hunter) < 48.0 and swing_cooldown <= 0.0:
		player_health -= 1
		swing_cooldown = 1.55
		damage_flash = 0.65
		camera_shake = 5.0
		alert = 2.6
		message = "THE WARDEN FOUND YOU"
		message_time = 1.5
		player = move_body(player, (player - hunter).normalized() * 45.0, 13.0)
		if player_health <= 0: finish("THE FOG CLAIMED YOU")

func update_hunter_ai(delta: float) -> void:
	var target := player
	var distance := hunter.distance_to(player)
	var speed := 103.0 if distance > 260.0 else 142.0
	hunter = move_body(hunter, hunter.direction_to(target) * speed * delta, 16.0)
	if distance < 250.0: alert = maxf(alert, 0.35)

func update_hunter_player(delta: float) -> void:
	var running := interacting() and hunter_stamina > 0.0
	var speed := 168.0 if running else 122.0
	hunter_stamina = clampf(hunter_stamina + (-30.0 if running else 17.0) * delta, 0.0, 100.0)
	hunter = move_body(hunter, movement_input() * speed * delta, 16.0)
	if attacking() and swing_cooldown <= 0.0:
		swing_cooldown = 0.72
		attack_flash = 0.26
		camera_shake = 3.0
		if hunter.distance_to(player) < 66.0:
			player_health -= 1
			damage_flash = 0.45
			message = "STRIKE LANDED"
			message_time = 1.0
			if player_health <= 0: finish("THE WARDEN PREVAILED")

func update_survivor_ai(delta: float) -> void:
	var generator_index := least_repaired_generator()
	var target := generators[generator_index]
	var distance := player.distance_to(target)
	if hunter.distance_to(player) < 160.0:
		target = Vector2(150, 610) if player.x > 640 else Vector2(1120, 610)
	player = move_body(player, player.direction_to(target) * 104.0 * delta, 13.0)
	if distance < 35.0 and repairs[generator_index] < 100.0:
		repairs[generator_index] = minf(100.0, repairs[generator_index] + 9.5 * delta)
	if repaired_count() == 3 and player.distance_to(exit_pos) < 40.0:
		finish("THE SURVIVOR ESCAPED")

func nearest_generator(pos: Vector2) -> int:
	var index := -1
	var closest := INF
	for i in generators.size():
		if repairs[i] < 100.0 and pos.distance_to(generators[i]) < closest:
			closest = pos.distance_to(generators[i])
			index = i
	return index

func least_repaired_generator() -> int:
	var best := 0
	for i in repairs.size():
		if repairs[i] < repairs[best]: best = i
	return best

func repaired_count() -> int:
	var count := 0
	for repair in repairs:
		if repair >= 100.0: count += 1
	return count

func finish(result: String) -> void:
	state = "result"
	game_result = result

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			state = "menu"
		if state == "result" and event.keycode in [KEY_ENTER, KEY_SPACE]: state = "menu"
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state == "menu":
			if Rect2(306, 487, 285, 61).has_point(event.position): start_game("survivor")
			if Rect2(690, 487, 285, 61).has_point(event.position): start_game("hunter")
		elif state == "result": state = "menu"

func panel(rect: Rect2, color: Color = Color("#151d20")) -> void:
	draw_rect(rect, color)
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("#5f746b"), 1.0)
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, Color("#263936"), 1.0)

func label_text(text: String, position: Vector2, size: int, color: Color = PAPER, alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, position, text, alignment, width, size, color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), INK)
	if state == "menu": draw_menu()
	elif state == "playing": draw_game()
	else: draw_result()

func draw_menu() -> void:
	for i in 12:
		var y := 82.0 + i * 54.0
		draw_line(Vector2(0, y), Vector2(1280, y - 18), Color(0.2, 0.31, 0.29, 0.13), 1.0)
	label_text("N I G H T F A L L", Vector2(0, 174), 72, PAPER, HORIZONTAL_ALIGNMENT_CENTER, 1280)
	label_text("THE LAST SIGNAL", Vector2(0, 213), 18, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 1280)
	draw_line(Vector2(458, 242), Vector2(822, 242), Color("#b46943"), 2)
	label_text("AN ASYMMETRIC NIGHTMARE", Vector2(0, 320), 17, MIST, HORIZONTAL_ALIGNMENT_CENTER, 1280)
	label_text("Keep the signal alive, or silence it forever.", Vector2(0, 350), 19, Color("#a7b4a8"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
	menu_button(Rect2(306, 487, 285, 61), "ENTER AS SURVIVOR", "WASD + E")
	menu_button(Rect2(690, 487, 285, 61), "ENTER AS WARDEN", "WASD + SPACE")
	label_text("SURVIVE THE NIGHT / 1 PLAYER VS AI", Vector2(0, 642), 13, Color("#718178"), HORIZONTAL_ALIGNMENT_CENTER, 1280)

func menu_button(rect: Rect2, title: String, small: String) -> void:
	draw_rect(rect, Color("#172123"))
	draw_rect(rect.grow(-2), Color("#101719"), false, 1.0)
	draw_line(Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), AMBER, 2.0)
	label_text(title, Vector2(rect.position.x, rect.position.y + 29), 17, PAPER, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	label_text(small, Vector2(rect.position.x, rect.position.y + 49), 11, MOSS, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func draw_game() -> void:
	# Map base and atmosphere.
	draw_rect(WORLD, Color("#172225"))
	for i in 12:
		var x := 57.0 + i * 101.0
		draw_line(Vector2(x, WORLD.position.y), Vector2(x - 135, WORLD.end.y), Color(0.26, 0.38, 0.35, 0.12), 2.0)
	for mote in motes:
		draw_circle(mote.p, 2.0, Color(0.76, 0.85, 0.77, mote.a))
	for crow in crows:
		draw_circle(crow, 3.0, Color("#0b1011"))
		draw_line(crow + Vector2(-5, 1), crow + Vector2(5, 1), Color("#0b1011"), 2)
	for rect in obstacles: draw_obstacle(rect)
	for i in generators.size(): draw_generator(i)
	draw_exit()
	draw_actor(hunter, true)
	draw_actor(player, false)
	draw_hud()
	if damage_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(BLOOD, damage_flash * 0.22))

func draw_obstacle(rect: Rect2) -> void:
	draw_rect(rect, Color("#263634"))
	draw_rect(rect.grow(-4), Color("#1c2a2a"))
	for x in range(int(rect.position.x + 9), int(rect.end.x), 18):
		draw_line(Vector2(x, rect.position.y + 4), Vector2(x - 9, rect.end.y - 4), Color("#4b5d50"), 2)

func draw_generator(index: int) -> void:
	var pos := generators[index]
	var progress: float = repairs[index]
	var active := progress >= 100.0
	draw_circle(pos, 31.0 + (sin(Time.get_ticks_msec() * 0.01) * 2.0 if active else 0.0), Color(AMBER, 0.10 if active else 0.025))
	draw_rect(Rect2(pos - Vector2(15, 17), Vector2(30, 34)), Color("#2b3635"))
	draw_rect(Rect2(pos - Vector2(10, 13), Vector2(20, 10)), AMBER if active else Color("#465452"))
	draw_line(pos + Vector2(-20, 18), pos + Vector2(20, 18), Color("#76806d"), 3)
	draw_rect(Rect2(pos + Vector2(-24, 27), Vector2(48, 5)), Color("#101617"))
	draw_rect(Rect2(pos + Vector2(-24, 27), Vector2(48 * progress / 100.0, 5)), AMBER)

func draw_exit() -> void:
	var ready := repaired_count() == 3
	draw_rect(Rect2(exit_pos - Vector2(31, 10), Vector2(62, 24)), Color("#202b2c"))
	draw_line(exit_pos + Vector2(-22, 14), exit_pos + Vector2(-22, 37), Color("#738074"), 3)
	draw_line(exit_pos + Vector2(22, 14), exit_pos + Vector2(22, 37), Color("#738074"), 3)
	draw_circle(exit_pos, 25.0, Color(AMBER, 0.25 if ready else 0.04))
	if ready: label_text("OPEN", exit_pos + Vector2(-23, -22), 11, AMBER)

func draw_actor(pos: Vector2, is_hunter: bool) -> void:
	var accent := RUST if is_hunter else Color("#b9d6ca")
	var body := Color("#3c2626") if is_hunter else Color("#29403b")
	draw_circle(pos + Vector2(0, 11), 14.0 if is_hunter else 12.0, body)
	draw_circle(pos + Vector2(0, -6), 8.0, accent)
	draw_line(pos + Vector2(-7, 18), pos + Vector2(7, 18), Color("#0d1515"), 3)
	if is_hunter:
		draw_line(pos + Vector2(10, 6), pos + Vector2(24, -5), RUST, 3)
		if attack_flash > 0: draw_arc(pos, 42, -0.8, 1.1, 16, Color(RUST, attack_flash * 3), 3)

func draw_hud() -> void:
	panel(Rect2(0, 0, 1280, 62), Color("#101719"))
	label_text("NIGHTFALL", Vector2(28, 38), 22, PAPER)
	label_text("THE LAST SIGNAL", Vector2(29, 54), 10, AMBER)
	var title := "SURVIVOR" if role == "survivor" else "WARDEN"
	label_text(title, Vector2(1005, 30), 14, AMBER)
	label_text("NIGHT %02d:%02d" % [int(time_alive) / 60, int(time_alive) % 60], Vector2(1005, 49), 12, MIST)
	for i in 3:
		var x := 538.0 + i * 70.0
		draw_rect(Rect2(x, 24, 52, 8), Color("#263232"))
		draw_rect(Rect2(x, 24, 52 * repairs[i] / 100.0, 8), AMBER if repairs[i] >= 100 else MOSS)
		label_text("%d" % (i + 1), Vector2(x + 20, 49), 11, PAPER)
	if role == "survivor":
		label_text("VITALITY", Vector2(30, 690), 11, MIST)
		for i in 2:
			draw_circle(Vector2(96 + i * 19, 685), 7, RUST if i < player_health else Color("#293332"))
		var gen := nearest_generator(player)
		if gen >= 0 and player.distance_to(generators[gen]) < 54 and repairs[gen] < 100:
			label_text("HOLD [E]  RESTORE RELAY", Vector2(450, 690), 14, PAPER, HORIZONTAL_ALIGNMENT_CENTER, 380)
		elif repaired_count() == 3 and player.distance_to(exit_pos) < 52:
			label_text("HOLD [E]  ESCAPE", Vector2(450, 690), 14, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 380)
		else: label_text("WASD  MOVE", Vector2(30, 710), 11, MIST)
	else:
		label_text("STAMINA", Vector2(30, 690), 11, MIST)
		draw_rect(Rect2(93, 682, 135, 8), Color("#293332"))
		draw_rect(Rect2(93, 682, 135 * hunter_stamina / 100.0, 8), RUST)
		label_text("[E] SPRINT    [SPACE] STRIKE", Vector2(30, 710), 11, MIST)
	if message_time > 0:
		label_text(message, Vector2(0, 99), 16, PAPER, HORIZONTAL_ALIGNMENT_CENTER, 1280)

func draw_result() -> void:
	for i in 7:
		draw_circle(Vector2(160 + i * 175, 160 + (i % 2) * 310), 180, Color("#213230", 0.32))
	label_text("THE NIGHT IS OVER", Vector2(0, 244), 19, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 1280)
	label_text(game_result, Vector2(0, 326), 48, PAPER, HORIZONTAL_ALIGNMENT_CENTER, 1280)
	var stat := "Relays restored: %d / 3" % repaired_count()
	label_text(stat, Vector2(0, 374), 18, MIST, HORIZONTAL_ALIGNMENT_CENTER, 1280)
	label_text("CLICK OR PRESS ENTER TO RETURN", Vector2(0, 516), 14, Color("#84958a"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
