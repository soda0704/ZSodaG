extends RefCounted
## Developer inventory operations. The ordinary workbench and campaign limit are unchanged.
const RECIPE = preload("res://assets/config/flamethrower_recipe.tres")
const COMMANDS := ["/flame parts", "/flame parts 2", "/flame assemble", "/flame disassemble", "/weapon flamethrower", "/item flamethrower", "/flame give large_cylinder", "/flame give small_cylinder", "/flame give cola_can", "/flame give pipe_bundle", "/flame give tape", "/flame give hardware_box", "/flame give pressure_gauge", "/flame give valve", "/item flame_large_cylinder", "/item flame_small_cylinder", "/item flame_cola_can", "/item flame_pipe_bundle", "/item flame_hardware_box", "/item flame_pressure_gauge", "/item flame_valve"]
static func part_type(alias: String) -> StringName:
	var kind:=StringName(alias.to_lower())
	if RECIPE.requirements.has(kind):return kind
	kind=StringName("flame_"+alias.to_lower())
	return kind if RECIPE.requirements.has(kind) else &""
static func description(command: String) -> String:
	match command:
		"/flame parts":return "Выдать полный набор деталей в инвентарь"
		"/flame parts 2":return "Выдать два полных набора деталей в инвентарь"
		"/flame assemble":return "Тестовая сборка из деталей: без верстака и сюжетного лимита"
		"/flame disassemble":return "Разобрать огнемёт в руках и вернуть один набор деталей"
		"/weapon flamethrower":return "Выдать готовый заправленный огнемёт"
		"/item flamethrower":return "Создать огнемёт в точке прицела"
	var args:=command.split(" ",false)
	var kind:=part_type(args[-1])
	return ("Выдать в инвентарь: " if args[0]=="/flame" else "Создать в точке прицела: ")+str(RECIPE.titles.get(kind,kind))
static func add_parts(player: GamePlayer, amounts: Dictionary, multiplier:=1) -> void:
	for kind in amounts:
		var count:=int(amounts[kind])*multiplier
		if kind==&"tape":player.tape_count+=count
		else:player.crafting_parts[kind]=int(player.crafting_parts.get(kind,0))+count
	player._publish_inventory()
static func execute(args: PackedStringArray, player: GamePlayer) -> String:
	if not player.multiplayer.is_server():return "Команда должна выполняться на сервере."
	if args.size()<2:return "Использование: /flame parts [1|2] | give <деталь> [число] | assemble | disassemble"
	if player.survival.dead or player.is_sleeping_in_bunk() or player.is_driving() or player.is_carrying_corpse() or player._battery_action_busy:
		return "Сейчас нельзя менять снаряжение: завершите текущее действие."
	match args[1]:
		"parts":
			if args.size()>3 or (args.size()==3 and (not args[2].is_valid_int() or int(args[2]) not in [1,2])):
				return "Использование: /flame parts [1|2]"
			var count:=int(args[2]) if args.size()==3 else 1
			add_parts(player,RECIPE.requirements,count)
			return "Полных наборов деталей выдано в инвентарь: %d."%count
		"give":
			if args.size() not in [3,4] or part_type(args[2])==&"":
				return "Детали: large_cylinder, small_cylinder, cola_can, pipe_bundle, tape, hardware_box, pressure_gauge, valve. /flame give <деталь> [число]"
			if args.size()==4 and (not args[3].is_valid_int() or int(args[3])<1 or int(args[3])>100):
				return "Количество должно быть целым числом от 1 до 100."
			var count:=int(args[3]) if args.size()==4 else 1
			var kind:=part_type(args[2]);add_parts(player,{kind:count})
			return "Выдано: %s ×%d."%[RECIPE.titles[kind],count]
		"assemble":
			if args.size()!=2:return "Использование: /flame assemble"
			if player.has_held_item(&"flamethrower"):return "Огнемёт уже в руках. Сначала /flame disassemble или выбросите его."
			if not RECIPE.can_craft(player):
				var missing:PackedStringArray=[];var owned:Dictionary=RECIPE.available(player)
				for kind in RECIPE.requirements:
					var count:=int(RECIPE.requirements[kind])-int(owned.get(kind,0))
					if count>0:missing.append("%s ×%d"%[RECIPE.titles[kind],count])
				return "Не хватает: "+", ".join(missing)+". /flame parts — выдать набор."
			if not player.pickup_world_item_authoritative(&"flamethrower",{}):return "Не удалось выдать огнемёт; детали сохранены."
			add_parts(player,RECIPE.requirements,-1)
			return "Огнемёт собран из деталей. Тестовая сборка не расходует сюжетный лимит."
		"disassemble":
			if args.size()!=2:return "Использование: /flame disassemble"
			if not player.has_held_item(&"flamethrower"):return "Для разборки возьмите огнемёт в руки."
			player.weapon.flame.stop_authoritative()
			if not player.consume_held_item_authoritative(&"flamethrower"):return "Не удалось разобрать огнемёт."
			add_parts(player,RECIPE.requirements)
			return "Огнемёт разобран: один полный набор деталей возвращён в инвентарь. Топливо при разборке не возвращается."
	return "Неизвестная операция. /flame parts | give <деталь> | assemble | disassemble"
