extends Node

var timeline_data = []
var current_index = 0
var is_paused = false
var voice_pos = 0.0
var music_pos = 0.0
var sfx_pos = 0.0
var choices = []
var awaiting_choice = false
var is_playing = false
var current_label = ""
var wait_remaining = 0.0  # 新增：记录等待事件的剩余时间

@onready var voice_audio = $VoiceAudio
@onready var music_audio = $MusicAudio
@onready var sfx_audio = $SFXAudio

const FADE_DURATION = 1.0

func play_timeline():
	if is_playing:
		print("时间线已在播放，忽略重复调用")
		return
	is_playing = true
	while current_index < timeline_data.size() and not awaiting_choice:
		if is_paused:  # 检查暂停状态
			is_playing = false
			return
		var event = timeline_data[current_index]
		var event_tag = event.get("tag", "")
		
		if event_tag == "" or event_tag == current_label:
			print("执行事件: ", event["type"], " at index: ", current_index, " with tag: ", event_tag)
			
			if current_index > 0 and event["type"] == "choice":
				var prev_event = timeline_data[current_index - 1]
				if prev_event["type"] == "audio" and prev_event["voice"] and voice_audio.stream:
					print("等待前一个 Voice 完成...")
					await voice_audio.finished
			
			match event["type"]:
				"audio":
					play_audio_event(event)
					if event["voice"] and voice_audio.stream:
						await voice_audio.finished
				"wait":
					var duration = event["duration"] - wait_remaining
					if duration > 0:
						await wait_with_interrupt(duration)  # 使用可中断的等待
					wait_remaining = 0.0  # 重置等待时间
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
					choices = event["options"]
					awaiting_choice = true
					is_playing = false
					return
				"vibrate":
					await wait_with_interrupt(event.get("duration", 1.0))
					wait_remaining = 0.0
		else:
			print("跳过事件: ", event["type"], " at index: ", current_index, " with tag: ", event_tag)
		current_index += 1
		wait_remaining = 0.0  # 确保每次事件完成后重置
	is_playing = false

func wait_with_interrupt(duration):
	var timer = get_tree().create_timer(duration)
	await timer.timeout
	if is_paused:
		wait_remaining = timer.time_left  # 记录剩余时间
		return

func set_label(label):
	current_label = label
	print("设置当前标签: ", current_label)

func play_audio_event(event):
	if event["voice"]:
		voice_audio.stream = load(event["voice"])
		voice_audio.play(voice_pos if is_paused else 0.0)  # 从暂停位置恢复
	if event["music"]:
		music_audio.stream = load(event["music"])
		fade_in(music_audio, music_pos if is_paused else 0.0)
	if event["sfx"]:
		sfx_audio.stream = load(event["sfx"])
		fade_in(sfx_audio, sfx_pos if is_paused else 0.0)
	is_paused = false  # 重置暂停状态以避免影响恢复

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

func toggle_pause():
	if not is_playing and not is_paused:
		print("没有预览在播放，无需暂停")
		return
	if not is_paused:
		voice_pos = voice_audio.get_playback_position()
		music_pos = music_audio.get_playback_position()
		sfx_pos = sfx_audio.get_playback_position()
		voice_audio.stop()
		if music_audio.playing:
			await fade_out(music_audio)
		if sfx_audio.playing:
			await fade_out(sfx_audio)
		is_paused = true
		is_playing = false
		print("预览已暂停, 当前索引: ", current_index, " 剩余等待时间: ", wait_remaining)
	else:
		is_paused = false
		if not awaiting_choice:
			play_timeline()  # 从当前索引继续
		print("预览已继续, 从索引: ", current_index, " 开始")

func stop_timeline():
	if is_playing or is_paused:
		voice_audio.stop()
		if music_audio.playing:
			await fade_out(music_audio)
		if sfx_audio.playing:
			await fade_out(sfx_audio)
		is_playing = false
		is_paused = false
		current_index = 0
		wait_remaining = 0.0
		awaiting_choice = false
		print("预览已停止")
