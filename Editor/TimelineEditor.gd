@tool
extends HSplitContainer

var events = []
var current_file_path = ""
var selected_event_index = -1
var needs_update = false
var is_playing = false

@onready var file_menu = $RightPanel/FileMenu
@onready var file_dialog = $FileDialog
@onready var event_list = $LeftPanel/EventScroll/EventList
@onready var status_label = $RightPanel/StatusLabel
@onready var total_time_label = $LeftPanel/TotalTimeLabel
@onready var preview = $Preview

var preview_player = AudioStreamPlayer.new()

const BASE_COLOR = Color(0.2, 0.2, 0.2)
const ACCENT_COLOR = Color(0.4, 0.6, 0.8)
const PREVIEW_COLOR = Color(0.6, 0.4, 0.8)
const EVENT_COLOR = Color(0.3, 0.5, 0.3)
const TEXT_COLOR = Color(0.9, 0.9, 0.9)

const EVENT_ICONS = {
	"audio": "▶ ",
	"wait": "⏳ ",
	"stop": "⏹ ",
	"choice": "🔀 ",
	"vibrate": "📳 ",
	"jump_timeline": "⏭ "  # 无图标
}

var button_normal_style: StyleBoxFlat
var button_hover_style: StyleBoxFlat
var button_pressed_style: StyleBoxFlat
var icon_button_normal_style: StyleBoxFlat
var icon_button_hover_style: StyleBoxFlat
var icon_button_pressed_style: StyleBoxFlat

func _ready():
	_init_button_styles()
	
	if not file_menu or not event_list or not preview:
		print("Error: One or more critical nodes not found!")
		return
	
	var file_grid = GridContainer.new()
	file_grid.columns = 2
	file_menu.add_child(file_grid)
	create_file_button(file_grid, "New", "🆕", "Create a new timeline", _on_new_button_pressed, ACCENT_COLOR)
	create_file_button(file_grid, "Open", "📂", "Open an existing timeline", _on_open_button_pressed, ACCENT_COLOR)
	
	var separator1 = HSeparator.new()
	separator1.custom_minimum_size = Vector2(0, 50)
	file_menu.add_child(separator1)
	
	var preview_grid = GridContainer.new()
	preview_grid.columns = 3
	preview_grid.add_theme_constant_override("hseparation", 15)
	preview_grid.add_theme_constant_override("vseparation", 10)
	file_menu.add_child(preview_grid)
	create_file_button(preview_grid, "Preview", "🎬", "Preview the timeline", _on_preview_button_pressed, PREVIEW_COLOR)
	create_file_button(preview_grid, "Pause", "⏸", "Pause/Resume preview", _on_pause_button_pressed, PREVIEW_COLOR)
	create_file_button(preview_grid, "Jump", "⏩", "Jump to specific event", _on_jump_button_pressed, PREVIEW_COLOR)
	
	var separator2 = HSeparator.new()
	separator2.custom_minimum_size = Vector2(0, 50)
	file_menu.add_child(separator2)
	
	var event_grid = GridContainer.new()
	event_grid.columns = 3
	event_grid.add_theme_constant_override("hseparation", 15)
	event_grid.add_theme_constant_override("vseparation", 10)
	file_menu.add_child(event_grid)
	create_event_button(event_grid, "Audio", EVENT_ICONS["audio"], "Add an audio event", _on_audio_button_pressed)
	create_event_button(event_grid, "Wait", EVENT_ICONS["wait"], "Add a wait event", _on_await_button_pressed)
	create_event_button(event_grid, "Stop", EVENT_ICONS["stop"], "Add a stop event", _on_stop_button_pressed)
	create_event_button(event_grid, "Choice", EVENT_ICONS["choice"], "Add a choice event", _on_choice_button_pressed)
	create_event_button(event_grid, "Vibrate", EVENT_ICONS["vibrate"], "Add a vibrate event", _on_vibrate_button_pressed)
	create_event_button(event_grid, "Next", EVENT_ICONS["jump_timeline"], "Add a jump timeline event", _on_jump_timeline_button_pressed)
	
	add_child(preview_player)
	preview.timeline_data = events
	if total_time_label:
		total_time_label.text = "Total Time: 00:00.000"
		total_time_label.add_theme_color_override("font_color", TEXT_COLOR)
	
	needs_update = true

func _process(_delta):
	if needs_update:
		update_event_list()
		update_total_time()
		preview.timeline_data = events
		needs_update = false

func _on_preview_button_pressed():
	if is_playing:
		stop_preview()
	else:
		if events.is_empty():
			show_status("No events to preview", Color(0.8, 0.6, 0.6))
			return
		is_playing = true
		preview.current_index = 0
		preview.is_paused = false
		preview.awaiting_choice = false
		preview.wait_remaining = 0.0
		show_status("Previewing timeline...", PREVIEW_COLOR)
		await preview_timeline()
		is_playing = preview.is_playing or preview.is_paused
		if not is_playing:
			show_status("Preview finished", PREVIEW_COLOR)

func _on_pause_button_pressed():
	if preview.is_playing or preview.is_paused:
		preview.toggle_pause()
		is_playing = preview.is_playing
		show_status("Preview " + ("paused" if preview.is_paused else "resumed"), PREVIEW_COLOR)
	else:
		show_status("No preview is playing", Color(0.8, 0.6, 0.6))

func _on_jump_button_pressed():
	if events.is_empty():
		show_status("No events to jump to", Color(0.8, 0.6, 0.6))
		return
	var dialog = AcceptDialog.new()
	dialog.title = "Jump to Event"
	dialog.dialog_text = "Enter event index (0 to " + str(events.size() - 1) + "):"
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "Event index"
	dialog.add_child(line_edit)
	dialog.connect("confirmed", _on_jump_confirmed.bind(line_edit))
	add_child(dialog)
	dialog.popup_centered()

func _on_jump_confirmed(line_edit):
	var index = int(line_edit.text)
	if index >= 0 and index < events.size():
		stop_preview()
		preview.current_index = index
		preview.wait_remaining = 0.0
		is_playing = true
		preview.is_paused = false
		preview.awaiting_choice = false
		show_status("Jumping to event " + str(index), PREVIEW_COLOR)
		await preview_timeline()
		is_playing = preview.is_playing or preview.is_paused
		if not is_playing:
			show_status("Preview finished", PREVIEW_COLOR)
	else:
		show_status("Invalid index: " + str(index), Color(0.8, 0.6, 0.6))

func stop_preview():
	if is_playing or preview.is_paused:
		preview.stop_timeline()
		is_playing = false
		show_status("Preview stopped", Color(0.8, 0.6, 0.6))

func preview_timeline():
	await preview.play_timeline()
	while preview.awaiting_choice and (is_playing or preview.is_paused):
		var choice_window = Window.new()
		choice_window.title = "Choose an Option"
		choice_window.size = Vector2(300, 150)
		choice_window.transient = true
		choice_window.exclusive = true
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		vbox.size_flags_vertical = SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 10)
		vbox.anchors_preset = Control.PRESET_FULL_RECT
		vbox.anchor_top = 0
		vbox.anchor_bottom = 1
		vbox.anchor_left = 0
		vbox.anchor_right = 1
		vbox.offset_top = 10
		vbox.offset_bottom = -10
		vbox.offset_left = 10
		vbox.offset_right = -10
		
		var label = Label.new()
		label.text = "Select an option:"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", TEXT_COLOR)
		vbox.add_child(label)
		
		for i in range(preview.choices.size()):
			var button = Button.new()
			button.text = preview.choices[i]["text"]
			apply_button_style(button, PREVIEW_COLOR.darkened(0.2))
			button.connect("pressed", _on_choice_selected.bind(i, choice_window))
			vbox.add_child(button)
		
		choice_window.add_child(vbox)
		add_child(choice_window)
		choice_window.popup_centered()
		
		await choice_window.close_requested
		choice_window.queue_free()

func _on_choice_selected(choice_index, window):
	preview.set_label(preview.choices[choice_index]["label"])
	preview.choices = []
	preview.awaiting_choice = false
	preview.current_index += 1
	window.hide()
	if is_playing and not preview.is_paused:
		await preview.play_timeline()
	is_playing = preview.is_playing or preview.is_paused

func _init_button_styles():
	button_normal_style = StyleBoxFlat.new()
	button_normal_style.bg_color = BASE_COLOR
	button_normal_style.set_corner_radius_all(8)
	button_normal_style.content_margin_left = 12
	button_normal_style.content_margin_right = 12
	button_normal_style.content_margin_top = 8
	button_normal_style.content_margin_bottom = 8
	button_normal_style.shadow_color = Color(0, 0, 0, 0.3)
	button_normal_style.shadow_size = 2
	
	button_hover_style = button_normal_style.duplicate()
	button_hover_style.bg_color = BASE_COLOR.lightened(0.3)
	
	button_pressed_style = button_normal_style.duplicate()
	button_pressed_style.bg_color = ACCENT_COLOR
	
	icon_button_normal_style = StyleBoxFlat.new()
	icon_button_normal_style.bg_color = Color(0.25, 0.25, 0.25, 0.9)
	icon_button_normal_style.set_corner_radius_all(6)
	icon_button_normal_style.content_margin_left = 8
	icon_button_normal_style.content_margin_right = 8
	icon_button_normal_style.shadow_color = Color(0, 0, 0, 0.2)
	icon_button_normal_style.shadow_size = 2
	
	icon_button_hover_style = icon_button_normal_style.duplicate()
	icon_button_hover_style.bg_color = Color(0.35, 0.35, 0.35, 0.9)
	
	icon_button_pressed_style = icon_button_normal_style.duplicate()
	icon_button_pressed_style.bg_color = ACCENT_COLOR.darkened(0.2)

func create_file_button(container, text: String, icon: String, tooltip: String, callback: Callable, bg_color: Color = BASE_COLOR):
	var button = Button.new()
	button.text = icon + " " + text
	button.tooltip_text = tooltip
	apply_button_style(button, bg_color)
	button.connect("pressed", callback)
	container.add_child(button)

func create_event_button(container, text: String, icon: String, tooltip: String, callback: Callable):
	var button = Button.new()
	button.text = icon + text
	button.tooltip_text = tooltip
	apply_button_style(button, EVENT_COLOR)
	button.connect("pressed", callback)
	container.add_child(button)

func apply_button_style(button, bg_color: Color = BASE_COLOR):
	button.size_flags_horizontal = SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(120, 40)
	var normal_style = button_normal_style.duplicate()
	normal_style.bg_color = bg_color
	button.add_theme_stylebox_override("normal", normal_style)
	
	var hover_style = button_hover_style.duplicate()
	hover_style.bg_color = bg_color.lightened(0.3)
	button.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style = button_pressed_style.duplicate()
	pressed_style.bg_color = bg_color.darkened(0.2)
	button.add_theme_stylebox_override("pressed", pressed_style)
	
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.connect("mouse_entered", _on_button_hover.bind(button, true))
	button.connect("mouse_exited", _on_button_hover.bind(button, false))

func apply_icon_button_style(button):
	button.flat = true
	button.custom_minimum_size = Vector2(32, 32)
	button.add_theme_stylebox_override("normal", icon_button_normal_style)
	button.add_theme_stylebox_override("hover", icon_button_hover_style)
	button.add_theme_stylebox_override("pressed", icon_button_pressed_style)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_font_size_override("font_size", 16)
	button.connect("mouse_entered", _on_button_hover.bind(button, true))
	button.connect("mouse_exited", _on_button_hover.bind(button, false))

func _on_button_hover(button, is_hovering):
	var tween = create_tween()
	tween.set_parallel(true)
	if is_hovering:
		tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.1)
		tween.tween_property(button, "modulate", Color(1.2, 1.2, 1.2), 0.1)
	else:
		tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.1)
		tween.tween_property(button, "modulate", Color(1.0, 1.0, 1.0), 0.1)

func show_status(message, color = TEXT_COLOR, duration = 2.0):
	if status_label.text != message:
		status_label.text = message
		status_label.modulate = color
		await get_tree().create_timer(duration).timeout
		status_label.text = ""
		status_label.modulate = TEXT_COLOR

func get_audio_duration(event):
	var paths = [event.get("voice", ""), event.get("music", ""), event.get("sfx", "")]
	var max_duration = 0.0
	for path in paths:
		if path != "" and ResourceLoader.exists(path):
			var audio = load(path)
			if audio is AudioStream:
				max_duration = max(max_duration, audio.get_length())
	return max_duration

func calculate_total_time():
	var total_time = 0.0
	for event in events:
		var event_type = event["type"]
		match event_type:
			"audio":
				total_time += get_audio_duration(event)
			"wait":
				total_time += event.get("duration", 1.0)
			"vibrate":
				total_time += event.get("duration", 1.0)
	return total_time

func format_duration(seconds):
	var minutes = int(seconds / 60)
	var secs = int(seconds) % 60
	var millis = int((seconds - int(seconds)) * 1000)
	return "%02d:%02d.%03d" % [minutes, secs, millis]

func update_total_time():
	if total_time_label:
		var total = calculate_total_time()
		total_time_label.text = "Total Time: " + format_duration(total)

func update_event_list():
	if not event_list:
		print("Error: event_list is null!")
		return
	
	for child in event_list.get_children():
		child.queue_free()
	
	for i in range(events.size()):
		var event = events[i]
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = SIZE_EXPAND_FILL
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
		style.set_corner_radius_all(8)
		if i == selected_event_index:
			style.bg_color = Color(0.2, 0.2, 0.2, 0.9)
			style.border_color = ACCENT_COLOR
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.border_width_left = 1
			style.border_width_right = 1
		style.shadow_color = Color(0, 0, 0, 0.2)
		style.shadow_size = 2
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		style.content_margin_left = 12
		style.content_margin_right = 12
		panel.add_theme_stylebox_override("panel", style)
		panel.connect("mouse_entered", _on_panel_mouse_entered.bind(i))
		panel.connect("mouse_exited", _on_panel_mouse_exited.bind(i))
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		
		var event_node = HBoxContainer.new()
		event_node.size_flags_horizontal = SIZE_EXPAND_FILL
		event_node.add_theme_constant_override("hseparation", 12)
		
		var index_label = Label.new()
		index_label.text = str(i + 1) + ". "
		index_label.add_theme_color_override("font_color", TEXT_COLOR)
		index_label.add_theme_font_size_override("font_size", 14)
		event_node.add_child(index_label)
		
		var info_container = HBoxContainer.new()
		info_container.size_flags_horizontal = SIZE_EXPAND_FILL
		info_container.add_theme_constant_override("hseparation", 8)
		
		var event_label = Label.new()
		var event_type = event["type"].capitalize()
		var icon = EVENT_ICONS.get(event["type"], "")
		var duration = 0.0
		var details = ""
		var tooltip_text = "Event " + str(i + 1) + ": " + event_type
		
		match event["type"]:
			"audio":
				var tag = event.get("tag", "")
				duration = get_audio_duration(event)
				if tag != "":
					details = "Tag: " + tag
					tooltip_text += "\nTag: " + tag
				tooltip_text += "\nDuration: " + format_duration(duration)
			"wait":
				duration = event.get("duration", 1.0)
				tooltip_text += "\nDuration: " + format_duration(duration)
			"stop":
				duration = 0.0
				if event.get("music", false):
					details += "Music "
					tooltip_text += "\nStop Music"
				if event.get("sfx", false):
					details += "SFX"
					tooltip_text += "\nStop SFX"
				details = details.strip_edges()
			"choice":
				duration = 0.0
				details = "2 Options"
				tooltip_text += "\nOptions: " + event["options"][0]["text"] + ", " + event["options"][1]["text"]
			"vibrate":
				duration = event.get("duration", 1.0)
				tooltip_text += "\nWeak: " + str(event.get("weak_magnitude", 0.3)) + "\nStrong: " + str(event.get("strong_magnitude", 0.5)) + "\nDuration: " + format_duration(duration)
			"jump_timeline":
				duration = 0.0
				var next_timeline = event.get("next_timeline", "")
				var tag = event.get("tag", "")
				details = next_timeline.get_file() if next_timeline else "No Target"
				if tag != "":
					details += " (Tag: " + tag + ")"
				tooltip_text += "\nNext Timeline: " + next_timeline
				if tag != "":
					tooltip_text += "\nTag: " + tag
		
		event_label.text = icon + event_type + (" - " + details if details else "")
		event_label.add_theme_color_override("font_color", TEXT_COLOR)
		event_label.add_theme_font_size_override("font_size", 14)
		event_label.tooltip_text = tooltip_text
		event_label.clip_text = true
		event_label.size_flags_horizontal = SIZE_EXPAND_FILL
		info_container.add_child(event_label)
		
		var duration_label = Label.new()
		duration_label.text = "[" + format_duration(duration) + "]"
		duration_label.add_theme_color_override("font_color", TEXT_COLOR.darkened(0.2))
		duration_label.add_theme_font_size_override("font_size", 12)
		duration_label.size_flags_horizontal = SIZE_SHRINK_END
		info_container.add_child(duration_label)
		
		event_node.add_child(info_container)
		
		var delete_button = Button.new()
		delete_button.text = "X"
		delete_button.tooltip_text = "Delete Event"
		apply_icon_button_style(delete_button)
		delete_button.connect("pressed", _on_delete_button_pressed.bind(i))
		event_node.add_child(delete_button)
		
		var up_button = Button.new()
		up_button.text = "↑"
		up_button.tooltip_text = "Move Up"
		apply_icon_button_style(up_button)
		up_button.connect("pressed", _on_move_up_pressed.bind(i))
		event_node.add_child(up_button)
		
		var down_button = Button.new()
		down_button.text = "↓"
		down_button.tooltip_text = "Move Down"
		apply_icon_button_style(down_button)
		down_button.connect("pressed", _on_move_down_pressed.bind(i))
		event_node.add_child(down_button)
		
		vbox.add_child(event_node)
		
		var properties_container = VBoxContainer.new()
		properties_container.name = "PropertiesContainer"
		properties_container.size_flags_horizontal = SIZE_EXPAND_FILL
		properties_container.add_theme_constant_override("separation", 8)
		if i == selected_event_index:
			update_properties_panel(properties_container, event)
		else:
			properties_container.visible = false
		vbox.add_child(properties_container)
		
		panel.add_child(vbox)
		event_list.add_child(panel)
		event_node.connect("gui_input", _on_event_node_gui_input.bind(i))
		if i == selected_event_index:
			animate_selection(panel)

func animate_selection(panel):
	var tween = create_tween()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.2).from(Color(1, 1, 1, 0.8))

func _on_panel_mouse_entered(index):
	if index != selected_event_index and index < event_list.get_child_count():
		var panel = event_list.get_child(index)
		var style = panel.get_theme_stylebox("panel").duplicate()
		style.bg_color = Color(0.18, 0.18, 0.18, 0.9)
		panel.add_theme_stylebox_override("panel", style)

func _on_panel_mouse_exited(index):
	if index != selected_event_index and index < event_list.get_child_count():
		var panel = event_list.get_child(index)
		var style = panel.get_theme_stylebox("panel").duplicate()
		style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
		panel.add_theme_stylebox_override("panel", style)

func _on_move_up_pressed(index):
	if index > 0 and index < events.size():
		swap_events(index, index - 1)
		if selected_event_index == index:
			selected_event_index -= 1
		elif selected_event_index == index - 1:
			selected_event_index += 1
		needs_update = true
		save_timeline()
		show_status("Moved event up from " + str(index + 1) + " to " + str(index), ACCENT_COLOR)

func _on_move_down_pressed(index):
	if index >= 0 and index < events.size() - 1:
		swap_events(index, index + 1)
		if selected_event_index == index:
			selected_event_index += 1
		elif selected_event_index == index + 1:
			selected_event_index -= 1
		needs_update = true
		save_timeline()
		show_status("Moved event down from " + str(index + 1) + " to " + str(index + 2), ACCENT_COLOR)

func swap_events(index1, index2):
	var temp = events[index1]
	events[index1] = events[index2]
	events[index2] = temp

func _on_audio_button_pressed():
	add_event("audio")

func _on_await_button_pressed():
	add_event("wait")

func _on_stop_button_pressed():
	add_event("stop")

func _on_choice_button_pressed():
	add_event("choice")

func _on_vibrate_button_pressed():
	add_event("vibrate")

func _on_jump_timeline_button_pressed():
	add_event("jump_timeline")

func add_event(event_type):
	var new_event = {}
	match event_type:
		"audio":
			new_event = {"type": "audio", "tag": "", "voice": "", "music": "", "sfx": ""}
		"wait":
			new_event = {"type": "wait", "duration": 1.0}
		"stop":
			new_event = {"type": "stop", "music": false, "sfx": false}
		"choice":
			new_event = {"type": "choice", "options": [{"text": "Option 1", "label": ""}, {"text": "Option 2", "label": ""}]}
		"vibrate":
			new_event = {"type": "vibrate", "weak_magnitude": 0.3, "strong_magnitude": 0.5, "duration": 1.0}
		"jump_timeline":
			new_event = {"type": "jump_timeline", "next_timeline": "", "tag": ""}
	events.append(new_event)
	needs_update = true
	save_timeline()
	show_status("Added " + event_type.capitalize() + " event", EVENT_COLOR)

func _on_event_node_gui_input(event, index):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if selected_event_index == index:
			selected_event_index = -1
		else:
			selected_event_index = index
		needs_update = true

func _on_delete_button_pressed(index):
	if index >= 0 and index < events.size():
		var event_type = events[index]["type"]
		events.remove_at(index)
		if selected_event_index == index:
			selected_event_index = -1
		elif selected_event_index > index:
			selected_event_index -= 1
		needs_update = true
		save_timeline()
		show_status("Deleted " + event_type.capitalize() + " event", EVENT_COLOR)

func update_properties_panel(container, event):
	for child in container.get_children():
		child.queue_free()
	
	container.visible = true
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("hseparation", 6)
	grid.add_theme_constant_override("vseparation", 4)
	
	match event["type"]:
		"audio":
			add_property_field(grid, "Tag", "tag", LineEdit.new())
			add_audio_path_field(grid, "Voice", "voice")
			add_audio_path_field(grid, "Music", "music")
			add_audio_path_field(grid, "SFX", "sfx")
		"wait":
			var spin_box = SpinBox.new()
			spin_box.value = event["duration"]
			spin_box.step = 0.1
			spin_box.min_value = 0.0
			spin_box.max_value = 999.9
			spin_box.size_flags_horizontal = SIZE_EXPAND_FILL
			apply_control_style(spin_box)
			spin_box.connect("value_changed", _on_duration_changed)
			add_property_field(grid, "Duration (s)", "duration", spin_box)
		"stop":
			var music_check = CheckBox.new()
			music_check.button_pressed = event["music"]
			music_check.connect("toggled", _on_stop_music_toggled)
			apply_control_style(music_check)
			add_property_field(grid, "Stop Music", "music", music_check)
			var sfx_check = CheckBox.new()
			sfx_check.button_pressed = event["sfx"]
			sfx_check.connect("toggled", _on_stop_sfx_toggled)
			apply_control_style(sfx_check)
			add_property_field(grid, "Stop SFX", "sfx", sfx_check)
		"choice":
			for i in range(2):
				var option = event["options"][i]
				var text_edit = LineEdit.new()
				text_edit.text = option["text"]
				text_edit.size_flags_horizontal = SIZE_EXPAND_FILL
				apply_control_style(text_edit)
				text_edit.connect("text_changed", _on_option_text_changed.bind(i))
				add_property_field(grid, "Option " + str(i+1) + " Text", "", text_edit)
				var label_edit = LineEdit.new()
				label_edit.text = option["label"]
				label_edit.size_flags_horizontal = SIZE_EXPAND_FILL
				apply_control_style(label_edit)
				label_edit.connect("text_changed", _on_option_label_changed.bind(i))
				add_property_field(grid, "Option " + str(i+1) + " Label", "", label_edit)
		"vibrate":
			var weak_spin = SpinBox.new()
			weak_spin.value = event["weak_magnitude"]
			weak_spin.step = 0.1
			weak_spin.min_value = 0.0
			weak_spin.max_value = 1.0
			weak_spin.size_flags_horizontal = SIZE_EXPAND_FILL
			apply_control_style(weak_spin)
			weak_spin.connect("value_changed", _on_weak_magnitude_changed)
			add_property_field(grid, "Weak Magnitude", "weak_magnitude", weak_spin)
			var strong_spin = SpinBox.new()
			strong_spin.value = event["strong_magnitude"]
			strong_spin.step = 0.1
			strong_spin.min_value = 0.0
			strong_spin.max_value = 1.0
			strong_spin.size_flags_horizontal = SIZE_EXPAND_FILL
			apply_control_style(strong_spin)
			strong_spin.connect("value_changed", _on_strong_magnitude_changed)
			add_property_field(grid, "Strong Magnitude", "strong_magnitude", strong_spin)
			var duration_spin = SpinBox.new()
			duration_spin.value = event["duration"]
			duration_spin.step = 0.1
			duration_spin.min_value = 0.0
			duration_spin.max_value = 999.9
			duration_spin.size_flags_horizontal = SIZE_EXPAND_FILL
			apply_control_style(duration_spin)
			duration_spin.connect("value_changed", _on_duration_changed)
			add_property_field(grid, "Duration (s)", "duration", duration_spin)
		"jump_timeline":
			var next_timeline_label = Label.new()
			next_timeline_label.text = "Next Timeline:"
			next_timeline_label.add_theme_color_override("font_color", TEXT_COLOR.darkened(0.1))
			next_timeline_label.add_theme_font_size_override("font_size", 14)
			next_timeline_label.custom_minimum_size = Vector2(120, 0)
			next_timeline_label.size_flags_horizontal = SIZE_SHRINK_BEGIN
			next_timeline_label.size_flags_vertical = SIZE_SHRINK_CENTER
			grid.add_child(next_timeline_label)
			
			var next_timeline_hbox = HBoxContainer.new()
			next_timeline_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
			next_timeline_hbox.add_theme_constant_override("hseparation", 4)
			
			var next_timeline_edit = LineEdit.new()
			next_timeline_edit.text = event["next_timeline"]
			next_timeline_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			apply_control_style(next_timeline_edit)
			next_timeline_edit.connect("text_changed", _on_next_timeline_changed)
			next_timeline_hbox.add_child(next_timeline_edit)
			
			var browse_button = Button.new()
			browse_button.text = "🔍"
			browse_button.tooltip_text = "Browse Timeline File"
			apply_icon_button_style(browse_button)
			browse_button.connect("pressed", _on_browse_timeline_pressed.bind(next_timeline_edit))
			next_timeline_hbox.add_child(browse_button)
			
			grid.add_child(next_timeline_hbox)
			
			var tag_edit = LineEdit.new()
			tag_edit.text = event["tag"]
			tag_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			apply_control_style(tag_edit)
			tag_edit.connect("text_changed", _on_property_text_changed.bind("tag"))
			add_property_field(grid, "Tag", "tag", tag_edit)
	
	container.add_child(grid)

func apply_control_style(control):
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.7)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.shadow_color = Color(0, 0, 0, 0.1)
	style.shadow_size = 1
	if control is LineEdit or control is SpinBox:
		control.add_theme_stylebox_override("normal", style)
		var focus_style = style.duplicate()
		focus_style.border_color = ACCENT_COLOR
		focus_style.border_width_top = 1
		focus_style.border_width_bottom = 1
		focus_style.border_width_left = 1
		focus_style.border_width_right = 1
		control.add_theme_stylebox_override("focus", focus_style)
		control.add_theme_color_override("font_color", TEXT_COLOR)
	if control is CheckBox:
		control.add_theme_color_override("font_color", TEXT_COLOR)

func add_property_field(container, label_text, property_key, control):
	var label = Label.new()
	label.text = label_text + ":"
	label.add_theme_color_override("font_color", TEXT_COLOR.darkened(0.1))
	label.add_theme_font_size_override("font_size", 14)
	label.custom_minimum_size = Vector2(120, 0)
	label.size_flags_horizontal = SIZE_SHRINK_BEGIN
	label.size_flags_vertical = SIZE_SHRINK_CENTER
	container.add_child(label)
	
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	if control is LineEdit and property_key != "":
		control.text = events[selected_event_index][property_key]
		if property_key != "next_timeline":
			control.connect("text_changed", _on_property_text_changed.bind(property_key))
	container.add_child(control)

func add_audio_path_field(container, label_text, property_key):
	var label = Label.new()
	label.text = label_text + ":"
	label.add_theme_color_override("font_color", TEXT_COLOR.darkened(0.1))
	label.add_theme_font_size_override("font_size", 14)
	label.custom_minimum_size = Vector2(120, 0)
	label.size_flags_horizontal = SIZE_SHRINK_BEGIN
	label.size_flags_vertical = SIZE_SHRINK_CENTER
	container.add_child(label)
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("hseparation", 6)
	
	var line_edit = LineEdit.new()
	line_edit.text = events[selected_event_index][property_key]
	line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	apply_control_style(line_edit)
	update_path_validation(line_edit, property_key)
	line_edit.connect("text_changed", _on_audio_path_changed.bind(property_key, line_edit))
	hbox.add_child(line_edit)
	
	var browse_button = Button.new()
	browse_button.text = "🔍"
	browse_button.tooltip_text = "Browse Audio File"
	apply_icon_button_style(browse_button)
	browse_button.connect("pressed", _on_browse_audio_pressed.bind(property_key, line_edit))
	hbox.add_child(browse_button)
	
	var play_button = Button.new()
	play_button.text = "▶"
	play_button.tooltip_text = "Play Audio"
	apply_icon_button_style(play_button)
	play_button.connect("pressed", _on_play_audio_pressed.bind(property_key))
	hbox.add_child(play_button)
	
	container.add_child(hbox)

func update_path_validation(line_edit, property_key):
	var path = events[selected_event_index][property_key]
	if path != "" and ResourceLoader.exists(path):
		line_edit.modulate = Color(0.6, 0.8, 0.6)
	else:
		line_edit.modulate = Color(0.8, 0.6, 0.6)

func _on_property_text_changed(new_text, property_key):
	events[selected_event_index][property_key] = new_text
	needs_update = true
	save_timeline()

func _on_audio_path_changed(new_text, property_key, line_edit):
	events[selected_event_index][property_key] = new_text
	update_path_validation(line_edit, property_key)
	needs_update = true
	save_timeline()
	if new_text != "" and not ResourceLoader.exists(new_text):
		show_status("Invalid audio path: " + new_text.get_file(), Color(0.8, 0.6, 0.6))

func _on_browse_audio_pressed(property_key, line_edit):
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.current_dir = "res://audio/"
	file_dialog.filters = ["*.wav", "*.mp3"]
	file_dialog.connect("file_selected", _on_audio_file_selected.bind(property_key, line_edit))
	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))

func _on_audio_file_selected(path, property_key, line_edit):
	events[selected_event_index][property_key] = path
	line_edit.text = path
	update_path_validation(line_edit, property_key)
	needs_update = true
	save_timeline()
	show_status("Audio path set: " + path.get_file(), Color(0.6, 0.8, 0.6))

func _on_play_audio_pressed(property_key):
	var path = events[selected_event_index][property_key]
	if path != "" and ResourceLoader.exists(path):
		preview_player.stream = load(path)
		preview_player.play()
		show_status("Playing: " + path.get_file(), Color(0.6, 0.8, 0.6))
	else:
		show_status("Cannot play, invalid path: " + path.get_file(), Color(0.8, 0.6, 0.6))

func _on_next_timeline_changed(new_text):
	events[selected_event_index]["next_timeline"] = new_text
	needs_update = true
	save_timeline()

func _on_browse_timeline_pressed(line_edit):
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.current_dir = "res://addons/AudioTimeline/Timelines/"
	file_dialog.filters = ["*.json"]
	file_dialog.connect("file_selected", _on_timeline_file_selected.bind(line_edit))
	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))

func _on_timeline_file_selected(path, line_edit):
	events[selected_event_index]["next_timeline"] = path
	line_edit.text = path
	needs_update = true
	save_timeline()
	show_status("Timeline path set: " + path.get_file(), Color(0.6, 0.8, 0.6))

func _on_duration_changed(value):
	events[selected_event_index]["duration"] = value
	needs_update = true
	save_timeline()

func _on_weak_magnitude_changed(value):
	events[selected_event_index]["weak_magnitude"] = value
	needs_update = true
	save_timeline()

func _on_strong_magnitude_changed(value):
	events[selected_event_index]["strong_magnitude"] = value
	needs_update = true
	save_timeline()

func _on_stop_music_toggled(button_pressed):
	events[selected_event_index]["music"] = button_pressed
	needs_update = true
	save_timeline()

func _on_stop_sfx_toggled(button_pressed):
	events[selected_event_index]["sfx"] = button_pressed
	needs_update = true
	save_timeline()

func _on_option_text_changed(new_text, option_index):
	events[selected_event_index]["options"][option_index]["text"] = new_text
	needs_update = true
	save_timeline()

func _on_option_label_changed(new_text, option_index):
	events[selected_event_index]["options"][option_index]["label"] = new_text
	needs_update = true
	save_timeline()

func _on_new_button_pressed():
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.current_dir = "res://addons/AudioTimeline/Timelines/"
	file_dialog.filters = ["*.json"]
	file_dialog.connect("file_selected", _on_new_file_selected)
	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))

func _on_new_file_selected(path):
	var dir = DirAccess.open("res://addons/AudioTimeline/Timelines/")
	if not dir:
		DirAccess.make_dir_absolute("res://addons/AudioTimeline/Timelines/")
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify([]))
		file.close()
		current_file_path = path
		events = []
		load_timeline(path)
		show_status("TimeLine created: " + path.get_file(), ACCENT_COLOR)
	else:
		show_status("Failed to create TimeLine: " + path.get_file(), Color(0.8, 0.6, 0.6))

func _on_open_button_pressed():
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.current_dir = "res://addons/AudioTimeline/Timelines/"
	file_dialog.filters = ["*.json"]
	file_dialog.connect("file_selected", _on_open_file_selected)
	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))

func _on_open_file_selected(path):
	load_timeline(path)

func load_timeline(path):
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()
		var result = JSON.parse_string(json_text)
		if result is Array:
			events = result
			current_file_path = path
			needs_update = true
			show_status("TimeLine loaded: " + path.get_file(), ACCENT_COLOR)
		else:
			show_status("Failed to parse JSON: " + path.get_file(), Color(0.8, 0.6, 0.6))
	else:
		show_status("Failed to open TimeLine: " + path.get_file(), Color(0.8, 0.6, 0.6))

func save_timeline():
	if current_file_path == "":
		show_status("No TimeLine file path specified", Color(0.8, 0.8, 0.6))
		return
	var file = FileAccess.open(current_file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(events))
		file.close()
	else:
		show_status("Failed to save TimeLine: " + current_file_path.get_file(), Color(0.8, 0.6, 0.6))
