@tool
extends EditorPlugin

@export var duration_seconds:float = 5
@export var transition_seconds:float = 1
@export var transition_distance:float = 540

var export_stripper:EditorExportPlugin = YouCanDoItExportStripper.new()
var overlay_dock:Control = load(addon_path.path_join("Scenes/OverlayDock.tscn")).instantiate()
var catalog_dock:Control = load(addon_path.path_join("Scenes/CatalogDock.tscn")).instantiate()
var messages:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(addon_path.path_join("Text/Messages.json")))

var speech_label:Label = overlay_dock.get_node(^"Background/SpeechBubble/SpeechLabel")
var girl_rect:TextureRect = overlay_dock.get_node(^"Background/Girl")
var audio_player:AudioStreamPlayer = overlay_dock.get_node(^"AudioPlayer")
var flow:FlowContainer = catalog_dock.get_node(^"Background/Scroll/Flow")
var portrait_template:TextureRect = flow.get_node(^"Portrait")
var counter_label:Label = catalog_dock.get_node(^"Background/Counter")
var filter_input:LineEdit = catalog_dock.get_node(^"Background/Filter")
var settings_button:BaseButton = catalog_dock.get_node(^"Background/Settings")
var settings_background:Panel = catalog_dock.get_node(^"Background/SettingsBackground")
var settings_information_label:Label = settings_background.get_node(^"Scroll/Box/Information")
var settings_interval_min_box:SpinBox = settings_background.get_node(^"Scroll/Box/Interval/Panel/MinBox")
var settings_interval_max_box:SpinBox = settings_background.get_node(^"Scroll/Box/Interval/Panel/MaxBox")

var is_application_focused:bool = true
var girl_debounce:bool = false
var girl_countdown_seconds:float = 0
var work_stopwatch_seconds:float = 0

const addon_path:String = "res://addons/YouCanDoIt"
const save_path:String = "user://YouCanDoItSave.json"

func _enter_tree()->void:
	reset_timer()
	overlay_dock.hide()
	# Add docks
	EditorInterface.get_editor_main_screen().add_child(overlay_dock)
	add_control_to_bottom_panel(catalog_dock, "Girl Catalog")
	# Add export stripper
	add_export_plugin(export_stripper)
	# Refresh initial catalog
	refresh_catalog()
	# Connect control events
	filter_input.text_changed.connect(filter_catalog)
	settings_button.pressed.connect(toggle_settings)
	settings_interval_min_box.value_changed.connect(func(_value): settings_interval_changed())
	settings_interval_max_box.value_changed.connect(func(_value): settings_interval_changed())

func _exit_tree()->void:
	# Remove docks
	overlay_dock.queue_free()
	remove_control_from_bottom_panel(catalog_dock)
	catalog_dock.queue_free()
	# Remove export stripper
	remove_export_plugin(export_stripper)

func _process(delta:float)->void:
	update_work_stopwatch(delta)
	update_girl_countdown(delta)

func _notification(what:int)->void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN:
			is_application_focused = true
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			is_application_focused = false

func update_work_stopwatch(delta:float)->void:
	# Ensure editor focused
	if not is_application_focused:
		return
	# Progress stopwatch
	work_stopwatch_seconds += delta
	# Add progressed minutes
	while work_stopwatch_seconds >= 60:
		work_stopwatch_seconds -= 60
		add_total_minutes(1)

func update_girl_countdown(delta:float)->void:
	# Progress timer
	girl_countdown_seconds -= delta
	if girl_countdown_seconds > 0: return
	reset_timer()
	
	# Debounce
	if girl_debounce: return
	girl_debounce = true
	
	# Wait until editor focused
	while not is_application_focused:
		await get_tree().create_timer(0.1).timeout
	
	# Show overlay
	var type:String = random_type()
	var girl:Texture2D = random_girl(type)
	speech_label.text = random_message(type)
	girl_rect.texture = girl
	overlay_dock.show()
	
	# Save girl as seen
	add_seen_girl_pathname(girl.resource_path)
	
	# Transition overlay in
	await transition_overlay(true)
	
	# Play sound
	audio_player.stream = random_sound()
	audio_player.play()
	
	# Wait duration
	await get_tree().create_timer(duration_seconds).timeout
	
	# Transition overlay out
	await transition_overlay(false)
	
	# Hide overlay
	overlay_dock.hide()
	
	# Reset debounce
	girl_debounce = false

func reset_timer()->void:
	var interval_minutes:Vector2 = load_interval_minutes()
	girl_countdown_seconds = randf_range(interval_minutes.x, interval_minutes.y) * 60

func random_type()->String:
	return messages.keys().pick_random()

func random_message(type:String)->String:
	return messages[type].pick_random()

func random_girl(type:String)->Texture2D:
	var girl_directory:String = addon_path.path_join("Images/Girls").path_join(type)
	var girl_paths:Array[String] = get_files_at(girl_directory)
	return load(girl_directory.path_join(girl_paths.pick_random()))

func random_sound()->AudioStream:
	var sound_directory:String = addon_path.path_join("Sounds")
	var sound_paths:Array[String] = get_files_at(sound_directory)
	return load(sound_directory.path_join(sound_paths.pick_random()))

func all_girl_paths()->Dictionary:
	var girl_paths:Dictionary = {}
	for type:String in messages.keys():
		var girl_directory:String = addon_path.path_join("Images/Girls").path_join(type)
		girl_paths[type] = get_files_at(girl_directory)
	return girl_paths

func transition_overlay(to_visible:bool)->void:
	var background:Control = overlay_dock.get_node(^"Background")
	var transition:Tween = get_tree().create_tween()
	
	if to_visible:
		background.position.y = transition_distance
		transition.tween_property(background, ^"position:y", 0, transition_seconds)
	else:
		background.position.y = 0
		transition.tween_property(background, ^"position:y", transition_distance, transition_seconds)
	
	await transition.finished

func refresh_catalog():
	# Get girl paths
	var all_paths:Dictionary = all_girl_paths()
	var seen_pathnames:Dictionary = load_seen_girl_pathnames()
	
	# Clear existing girls
	for portrait:Node in flow.get_children():
		if portrait == portrait_template:
			continue
		portrait.queue_free()
	
	# Count girls
	var unseen_count:int = 0
	var seen_count:int = 0
	
	# Add each girl to catalog
	for type:String in all_paths:
		for girl_path:String in all_paths[type]:
			var girl_pathname = girl_path.get_basename()
			
			# Create new portrait
			var portrait:TextureRect = portrait_template.duplicate()
			# Set portrait texture to girl
			portrait.texture = load(addon_path.path_join("Images/Girls").path_join(type).path_join(girl_path))
			
			# Show girl if seen
			if seen_pathnames.has(girl_pathname):
				seen_count += 1
				portrait.tooltip_text = \
					girl_pathname \
					+ "\nType: {0}".format([type]) \
					+ "\nSeen: {0} times".format([seen_pathnames[girl_pathname]])
			# Lock girl if not seen
			else:
				unseen_count += 1
				portrait.self_modulate = Color.BLACK
				portrait.tooltip_text = "Locked"
			
			# Add girl to catalog
			portrait.show()
			flow.add_child(portrait)
			
			# Wait to prevent freezing
			if ((seen_count + unseen_count) % 15 == 0):
				await get_tree().process_frame
	
	# Render counter
	counter_label.text = "Seen: {0}/{1}".format([seen_count, seen_count + unseen_count])
	if unseen_count == 0:
		counter_label.text = "Seen: all {0}!".format([seen_count])

func save_progress(progress:Dictionary)->void:
	var save_file:FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	save_file.store_string(JSON.stringify(progress, "\t"))
	save_file.close()

func load_progress()->Dictionary:
	var save_file:String = FileAccess.get_file_as_string(save_path)
	if save_file.is_empty(): return {}
	return JSON.parse_string(save_file)

func add_total_minutes(minutes:int)->void:
	var progress:Dictionary = load_progress()
	progress["total_minutes"] = progress.get_or_add("total_minutes", 0) + minutes
	save_progress(progress)

func load_total_minutes()->int:
	var progress:Dictionary = load_progress()
	return progress.get_or_add("total_minutes", 0)

func set_interval_minutes(minutes:Vector2)->void:
	var progress:Dictionary = load_progress()
	progress["min_interval_minutes"] = minutes.x
	progress["max_interval_minutes"] = minutes.y
	save_progress(progress)

func load_interval_minutes()->Vector2:
	var progress:Dictionary = load_progress()
	return Vector2(
		progress.get_or_add("min_interval_minutes", 15.0),
		progress.get_or_add("max_interval_minutes", 30.0)
	)

func add_seen_girl_pathname(girl_pathname:String)->void:
	girl_pathname = girl_pathname.get_file().get_basename()
	var progress:Dictionary = load_progress()
	var seen_girls:Dictionary = progress.get_or_add("seen", {})
	seen_girls[girl_pathname] = seen_girls.get_or_add(girl_pathname, 0) + 1
	save_progress(progress)
	refresh_catalog()

func load_seen_girl_pathnames()->Dictionary:
	var progress:Dictionary = load_progress()
	return progress.get_or_add("seen", {})

func filter_catalog(filter:String = "")->void:
	for portrait:Node in flow.get_children():
		if portrait == portrait_template:
			continue
		if filter.is_empty():
			portrait.show()
		elif portrait.self_modulate == Color.BLACK:
			portrait.hide()
		else:
			var girl_pathname:String = portrait.texture.resource_path.get_file().get_basename()
			portrait.visible = girl_pathname.to_lower().contains(filter.to_lower())

func toggle_settings()->void:
	settings_background.visible = not settings_background.visible
	
	settings_information_label.text = \
		"Total Minutes: {0}".format([load_total_minutes()]) \
		+ "\nPlugin Version: {0}".format([get_plugin_version()])
	
	var interval_minutes:Vector2 = load_interval_minutes()
	settings_interval_min_box.value = interval_minutes.x
	settings_interval_max_box.value = interval_minutes.y

func settings_interval_changed()->void:
	set_interval_minutes(Vector2(
		settings_interval_min_box.value,
		settings_interval_max_box.value
	))

static func get_files_at(directory:String)->Array[String]:
	var files:Array[String] = []
	for file:String in DirAccess.get_files_at(directory):
		if file.ends_with(".import"):
			files.append(file.trim_suffix(".import"))
	return files

class YouCanDoItExportStripper extends EditorExportPlugin:
	func _export_file(path:String, type:String, features:PackedStringArray)->void:
		# Strip plugin files from export
		if path.begins_with(addon_path.path_join("")):
			skip()
