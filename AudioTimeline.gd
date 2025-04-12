extends Node

@export var timeline_path: String = "res://addons/AudioTimeline/Timelines/cycle_02.json"
var timeline_data = []
var current_index = 0
var is_paused = false
var voice_pos = 0.0
var music_pos = 0.0
var sfx_pos = 0.0
var choices = []
var awaiting_choice = false
var is_playing = false
var is_vibrating = false
var current_label = ""
var next_timeline_path: String = ""

@onready var voice_audio = $VoiceAudio
@onready var music_audio = $MusicAudio
@onready var sfx_audio = $SFXAudio
var voices = DisplayServer.tts_get_voices_for_language("zh")
var voice_id = voices[0]

const FADE_DURATION = 1.0

func _ready():
	load_timeline(timeline_path)

func load_timeline(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()
		var json_result = JSON.parse_string(json_text)
		if json_result is Array and json_result.size() > 0:
			timeline_data = json_result
			timeline_path = path
			current_index = 0
			current_label = ""
			print("成功加载时间线文件: ", path)
		else:
			print("时间线文件内容无效或为空: ", path)
			timeline_data = []
	else:
		print("无法加载时间线文件: ", path)
		timeline_data = []

func _process(_delta):
	if Input.is_action_just_pressed("pause_save"):
		toggle_pause()
		save_game()
	if Input.is_action_just_pressed("resume_game") and is_paused:
		toggle_pause()
	
	if awaiting_choice and choices.size() > 0 and not is_paused:
		if Input.is_action_just_pressed("choice_left") and choices.size() >= 1:
			print("选择了选项 1: ", choices[0]["text"])
			stop_vibration()
			trigger_vibration(0, 0.5, 0, 0.5)
			set_label(choices[0]["label"])
			choices = []
			awaiting_choice = false
			current_index += 1
			if not is_paused:
				play_timeline()
		elif Input.is_action_just_pressed("choice_right") and choices.size() >= 2:
			print("选择了选项 2: ", choices[1]["text"])
			stop_vibration()
			trigger_vibration(0, 0, 0.5, 0.5)
			set_label(choices[1]["label"])
			choices = []
			awaiting_choice = false
			current_index += 1
			if not is_paused:
				play_timeline()

# 修改：为 jump_timeline 添加 tag 过滤
func play_timeline():
	if is_playing:
		print("时间线已在播放，忽略重复调用")
		return
	is_playing = true
	
	if timeline_data.size() == 0:
		print("时间线数据为空，无法播放")
		is_playing = false
		return
	
	while current_index < timeline_data.size() and not is_paused and not awaiting_choice:
		var event = timeline_data[current_index]
		
		if not event is Dictionary:
			print("错误：事件不是字典类型 at index: ", current_index, " 数据: ", event)
			current_index += 1
			continue
		if not "type" in event:
			print("错误：事件缺少 'type' 键 at index: ", current_index, " 数据: ", event)
			current_index += 1
			continue
		
		var event_tag = event.get("tag", "")
		
		# 只执行 tag 匹配或无 tag 的事件
		if event_tag == "" or event_tag == current_label:
			print("执行事件: ", event["type"], " at index: ", current_index, " with tag: ", event_tag)
			
			if current_index > 0 and event["type"] == "choice":
				var prev_event = timeline_data[current_index - 1]
				if prev_event is Dictionary and prev_event.get("type") == "audio" and prev_event.get("voice") and voice_audio.stream:
					print("等待前一个 Voice 完成...")
					await voice_audio.finished
			
			match event["type"]:
				"audio":
					play_audio_event(event)
					if event.get("voice") and voice_audio.stream:
						await voice_audio.finished
				"wait":
					await get_tree().create_timer(event.get("duration", 1.0)).timeout
				"stop":
					if event.get("music", false):
						await fade_out(music_audio)
						music_audio.stream = null
						music_pos = 0.0
						print("停止 Music")
					if event.get("sfx", false):
						await fade_out(sfx_audio)
						sfx_audio.stream = null
						sfx_pos = 0.0
						print("停止 SFX")
				"choice":
					choices = event.get("options", [])
					if choices.size() > 0:
						awaiting_choice = true
						show_choices()
						is_playing = false
						return
					else:
						print("错误：选择事件缺少有效选项 at index: ", current_index)
						current_index += 1
				"vibrate":
					start_vibrate(event.get("weak_magnitude", 0.3), event.get("strong_magnitude", 0.5), event.get("duration", 1.0))
				"jump_timeline":
					# jump_timeline 事件已受 tag 过滤，无需额外检查
					next_timeline_path = event.get("next_timeline", "")
					if next_timeline_path != "":
						print("准备跳转到新时间线: ", next_timeline_path)
						is_playing = false
						load_timeline(next_timeline_path)
						next_timeline_path = ""
						play_timeline()
						return
					else:
						print("未指定下一个时间线路径，忽略跳转")
		else:
			print("跳过事件: ", event["type"], " at index: ", current_index, " with tag: ", event_tag)
		current_index += 1
	
	if current_index >= timeline_data.size() and not awaiting_choice and not is_paused:
		if next_timeline_path != "":
			print("当前时间线播放完毕，跳转到: ", next_timeline_path)
			load_timeline(next_timeline_path)
			next_timeline_path = ""
			is_playing = false
			play_timeline()
		else:
			print("时间线播放完毕，无下一个时间线可跳转")
	
	is_playing = false

func set_label(label):
	current_label = label
	print("设置当前标签: ", current_label)

func play_audio_event(event):
	if event.get("voice"):
		voice_audio.stream = load(event["voice"])
		voice_audio.play()
	if event.get("music"):
		music_audio.stream = load(event["music"])
		fade_in(music_audio)
	if event.get("sfx"):
		sfx_audio.stream = load(event["sfx"])
		fade_in(sfx_audio)

func fade_in(audio_player, start_pos = 0.0):
	audio_player.volume_db = -80
	audio_player.play(start_pos)
	var tween = create_tween()
	tween.tween_property(audio_player, "volume_db", 0, FADE_DURATION)

func fade_out(audio_player):
	if audio_player.playing:
		var tween = create_tween()
		tween.tween_property(audio_player, "volume_db", -80, FADE_DURATION)
		await tween.finished
		audio_player.stop()

func show_choices():
	sfx_audio.stream = load("res://audio/ui-button-press.wav")
	sfx_audio.play()
	var prompt = "请选择。选项 1: " + choices[0]["text"] + "，按 LT 键。"
	if choices.size() >= 2:
		prompt += " 选项 2: " + choices[1]["text"] + "，按 RT 键。"
	DisplayServer.tts_speak(prompt, voice_id)
	print("等待玩家选择: ", prompt)
	start_vibration()

func start_vibration():
	if is_vibrating:
		return
	is_vibrating = true
	while is_vibrating and awaiting_choice and not is_paused:
		Input.start_joy_vibration(0, 0.3, 0.5, 0.5)
		await get_tree().create_timer(1.0).timeout
	Input.stop_joy_vibration(0)

func stop_vibration():
	is_vibrating = false
	Input.stop_joy_vibration(0)

func trigger_vibration(left_weak: float, left_strong: float, right_weak: float, right_strong: float, duration: float = 0.5):
	var weak_magnitude = max(left_weak, right_weak)
	var strong_magnitude = max(left_strong, right_strong)
	Input.start_joy_vibration(0, weak_magnitude, strong_magnitude, duration)
	fork_vibrate(duration)

func start_vibrate(weak_magnitude: float, strong_magnitude: float, duration: float):
	Input.start_joy_vibration(0, weak_magnitude, strong_magnitude, duration)
	fork_vibrate(duration)

func fork_vibrate(duration: float):
	await get_tree().create_timer(duration).timeout
	Input.stop_joy_vibration(0)
	print("震动结束")

func toggle_pause():
	if not is_paused:
		voice_pos = voice_audio.get_playback_position()
		music_pos = music_audio.get_playback_position()
		sfx_pos = sfx_audio.get_playback_position()
		voice_audio.stop()
		if music_audio.playing:
			await fade_out(music_audio)
		if sfx_audio.playing:
			await fade_out(sfx_audio)
		stop_vibration()
		is_paused = true
		DisplayServer.tts_speak("游戏已暂停。", voice_id)
	else:
		if voice_audio.stream:
			voice_audio.play(voice_pos)
		if music_audio.stream:
			fade_in(music_audio, music_pos)
		if sfx_audio.stream:
			fade_in(sfx_audio, sfx_pos)
		is_paused = false
		if awaiting_choice:
			start_vibration()
		DisplayServer.tts_speak("游戏已继续。", voice_id)

func save_game():
	var save_data = {
		"current_index": current_index,
		"voice_pos": voice_pos,
		"music_pos": music_pos,
		"sfx_pos": sfx_pos,
		"current_label": current_label,
		"timeline_path": timeline_path,
		"next_timeline_path": next_timeline_path
	}
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("user://saves"):
		dir.make_dir("saves")
	var file = FileAccess.open("user://saves/my_slot.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()
	DisplayServer.tts_speak("游戏已保存。", voice_id)

func load_game():
	var file = FileAccess.open("user://saves/my_slot.json", FileAccess.READ)
	if file:
		var save_data = JSON.parse_string(file.get_as_text())
		file.close()
		current_index = save_data["current_index"]
		voice_pos = save_data["voice_pos"]
		music_pos = save_data["music_pos"]
		sfx_pos = save_data["sfx_pos"]
		current_label = save_data["current_label"]
		timeline_path = save_data["timeline_path"]
		next_timeline_path = save_data["next_timeline_path"]
		load_timeline(timeline_path)
		play_timeline()
