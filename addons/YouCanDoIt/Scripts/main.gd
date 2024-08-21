@tool
extends EditorPlugin

@export var min_interval_minutes:float = 15
@export var max_interval_minutes:float = 30
@export var duration_seconds:float = 5
@export var transition_seconds:float = 1
@export var transition_distance:float = 540
@export var volume_db:float = -10

var overlay_dock:Control = load(addon_path.path_join("Scenes/OverlayDock.tscn")).instantiate()
var messages:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(addon_path.path_join("Text/Messages.json")))
var timer_seconds:float = 0

const addon_path:String = "res://addons/YouCanDoIt"

func _enter_tree()->void:
	reset_timer()
	overlay_dock.hide()
	# Setup docks
	EditorInterface.get_editor_main_screen().add_child(overlay_dock)

func _exit_tree()->void:
	# Cleanup docks
	overlay_dock.queue_free()

func _process(delta:float)->void:
	# Debounce
	if overlay_dock.visible: return
	
	# Progress timer
	timer_seconds -= delta
	if timer_seconds > 0: return
	reset_timer()
	
	# Show overlay
	var type:String = random_type()
	overlay_dock.get_node("Background/SpeechBubble/SpeechLabel").text = random_message(type)
	overlay_dock.get_node("Background/Girl").texture = random_girl(type)
	overlay_dock.show()
	
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

func get_files_at(directory:String)->Array:
	var files:Array = []
	for file:String in DirAccess.get_files_at(directory):
		if file.ends_with(".import"):
			files.append(file.trim_suffix(".import"))
	return files
