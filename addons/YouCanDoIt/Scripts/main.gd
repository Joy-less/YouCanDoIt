@tool
extends EditorPlugin

@export var min_interval_minutes:float = 15
@export var max_interval_minutes:float = 30
@export var duration_seconds:float = 5
@export var transition_seconds:float = 1
@export var transition_distance:float = 540
@export var volume_db:float = -10

var export_stripper:EditorExportPlugin = YouCanDoItExportStripper.new()
var overlay_dock:Control = load(addon_path.path_join("Scenes/OverlayDock.tscn")).instantiate()
var catalog_dock:Control = load(addon_path.path_join("Scenes/CatalogDock.tscn")).instantiate()
var messages:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(addon_path.path_join("Text/Messages.json")))
var timer_seconds:float = 0

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
	# Fill initial catalog
	fill_catalog()

func _exit_tree()->void:
	# Remove docks
	overlay_dock.queue_free()
	remove_control_from_bottom_panel(catalog_dock)
	catalog_dock.queue_free()
	# Remove export stripper
	remove_export_plugin(export_stripper)

func _process(delta:float)->void:
	# Debounce
	if overlay_dock.visible: return
	
	# Progress timer
	timer_seconds -= delta
	if timer_seconds > 0: return
	reset_timer()
	
	# Show overlay
	var type:String = random_type()
	var girl:Texture2D = random_girl(type)
	overlay_dock.get_node("Background/SpeechBubble/SpeechLabel").text = random_message(type)
	overlay_dock.get_node("Background/Girl").texture = girl
	overlay_dock.show()
	
	# Save girl as seen
	save_seen_girl(girl.resource_path)
	
	# Transition overlay in
	await transition_overlay(true)
	
	# Play sound
	var audio_player:AudioStreamPlayer = overlay_dock.get_node("AudioPlayer")
	audio_player.stream = random_sound()
	audio_player.volume_db = volume_db
	audio_player.play()
	
	# Wait duration
	await get_tree().create_timer(duration_seconds).timeout
	
	# Transition overlay out
	await transition_overlay(false)
	
	# Hide overlay
	overlay_dock.hide()

func reset_timer()->void:
	timer_seconds = randf_range(min_interval_minutes, max_interval_minutes) * 60

func random_type()->String:
	return messages.keys().pick_random()

func random_message(type:String)->String:
	return messages[type].pick_random()

func random_girl(type:String)->Texture2D:
	var girl_directory:String = addon_path.path_join("Images/Girls").path_join(type)
	var girl_paths:Array = get_files_at(girl_directory)
	return load(girl_directory.path_join(girl_paths.pick_random()))

func random_sound()->AudioStream:
	var sound_directory:String = addon_path.path_join("Sounds")
	var sound_paths:Array = get_files_at(sound_directory)
	return load(sound_directory.path_join(sound_paths.pick_random()))

func all_girl_paths()->Dictionary:
	var girl_paths:Dictionary = {}
	for type:String in messages.keys():
		var girl_directory:String = addon_path.path_join("Images/Girls").path_join(type)
		girl_paths[type] = get_files_at(girl_directory)
	return girl_paths

func transition_overlay(to_visible:bool)->void:
	var background:Control = overlay_dock.get_node("Background")
	var transition:Tween = get_tree().create_tween()
	
	if to_visible:
		background.position.y = transition_distance
		transition.tween_property(background, "position:y", 0, transition_seconds)
	else:
		background.position.y = 0
		transition.tween_property(background, "position:y", transition_distance, transition_seconds)
	
	await transition.finished

func fill_catalog():
	# Get girl paths
	var all_paths:Dictionary = all_girl_paths()
	var seen_paths:Dictionary = seen_girl_paths()
	
	# Get catalog container
	var flow:FlowContainer = catalog_dock.get_node("Background/Scroll/Flow")
	var portrait_template:TextureRect = flow.get_node("Portrait")
	
	# Clear existing girls
	for portrait:Node in flow.get_children():
		if portrait != portrait_template:
			portrait.queue_free()
	
	# Add each girl to catalog
	for type:String in all_paths:
		for girl_path:String in all_paths[type]:
			var girl_pathname = girl_path.get_basename()
			
			# Create new portrait
			var portrait:TextureRect = portrait_template.duplicate()
			# Set portrait texture to girl
			portrait.texture = load(addon_path.path_join("Images/Girls").path_join(type).path_join(girl_path))
			
			# Show girl if seen
			if seen_paths.has(girl_pathname):
				portrait.tooltip_text = girl_pathname \
					+ "\nType: " + type \
					+ "\nSeen: " + str(seen_paths[girl_pathname]) + " times"
			# Lock girl if not seen
			else:
				portrait.self_modulate = Color.BLACK
				portrait.tooltip_text = "Locked"
			
			# Add girl to catalog
			portrait.show()
			flow.add_child(portrait)
			
			# Wait to prevent freezing
			await get_tree().process_frame

func save_progress(progress:Dictionary)->void:
	var save_file:FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	save_file.store_string(JSON.stringify(progress))
	save_file.close()

func load_progress()->Dictionary:
	var save_file:String = FileAccess.get_file_as_string(save_path)
	if save_file.is_empty(): return {}
	return JSON.parse_string(save_file)

func save_seen_girl(girl_pathname:String)->void:
	girl_pathname = girl_pathname.get_file().get_basename()
	var progress:Dictionary = load_progress()
	var seen_girls:Dictionary = progress.get_or_add("seen", {})
	seen_girls[girl_pathname] = seen_girls.get_or_add(girl_pathname, 0) + 1
	save_progress(progress)
	fill_catalog()

func seen_girl_paths()->Dictionary:
	var progress:Dictionary = load_progress()
	return progress.get_or_add("seen", {})

static func get_files_at(directory:String)->Array:
	var files:Array = []
	for file:String in DirAccess.get_files_at(directory):
		if file.ends_with(".import"):
			files.append(file.trim_suffix(".import"))
	return files

class YouCanDoItExportStripper extends EditorExportPlugin:
	func _export_file(path:String, type:String, features:PackedStringArray)->void:
		# Strip plugin files from export
		if path.begins_with(addon_path):
			skip()
