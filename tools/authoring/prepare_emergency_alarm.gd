extends SceneTree
## Decode with Godot, downmix L/R to mono, and author a native light envelope.
const OUTPUT := "res://assets/audio/gameplay/emergency_alarm/"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source=arg.trim_prefix("--source=")
	if source.is_empty():push_error("Pass --source=path-to-mp3");quit(1);return
	var mp3:=AudioStreamMP3.new();mp3.data=FileAccess.get_file_as_bytes(source)
	var playback:=mp3.instantiate_playback();playback.start()
	var rate:=int(AudioServer.get_mix_rate())
	var expected:=int(mp3.get_length()*rate)
	var samples:=PackedFloat32Array()
	var stereo_difference:=0.0
	while samples.size()<expected:
		var frames:=playback.mix_audio(1.0,mini(2048,expected-samples.size()))
		if frames.is_empty():break
		for frame in frames:
			samples.append((frame.x+frame.y)*.5)
			stereo_difference+=absf(frame.x-frame.y)
	playback.stop()
	var data:=PackedByteArray();data.resize(samples.size()*2)
	var peak:=0.0;var power:=0.0
	for index in samples.size():
		var value:=clampf(samples[index],-1,1)
		data.encode_s16(index*2,roundi(value*32767))
		peak=maxf(peak,absf(value));power+=value*value
	var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate=rate;wav.stereo=false;wav.data=data
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	if wav.save_to_wav(OUTPUT+"emergency_alarm_mono.wav")!=OK:quit(1);return
	var energies:Array[float]=[]
	var window:=maxi(1,roundi(rate*.02))
	for start in range(0,samples.size(),window):
		var sum:=0.0;var end:=mini(start+window,samples.size())
		for index in range(start,end):sum+=samples[index]*samples[index]
		energies.append(sqrt(sum/maxi(1,end-start)))
	var sorted:=energies.duplicate();sorted.sort()
	var low:float=sorted[int((sorted.size()-1)*.05)]
	var high:float=sorted[int((sorted.size()-1)*.95)]
	var animation:=Animation.new();animation.length=float(samples.size())/rate
	animation.loop_mode=Animation.LOOP_LINEAR
	var track:=animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track,NodePath(".:intensity"))
	var intensity:=.15
	var minimum:=1.0;var maximum:=0.0
	# Two passes settle the envelope across the loop seam before recording keys.
	for cycle in 2:
		for index in energies.size():
			var level:=clampf((energies[index]-low)/maxf(high-low,.000001),0,1)
			var target:=lerpf(.15,1.0,pow(level,.7))
			intensity=lerpf(intensity,target,1.0-exp(-.02/(.025 if target>intensity else .12)))
			if cycle==1:
				animation.track_insert_key(track,float(index*window)/rate,intensity)
				minimum=minf(minimum,intensity);maximum=maxf(maximum,intensity)
	ResourceSaver.save(animation,OUTPUT+"emergency_alarm_pulse.tres")
	var report:={"source_sha256":FileAccess.get_sha256(source),"channels":1,"rate":rate,"frames":samples.size(),"seconds":animation.length,"peak":peak,"rms":sqrt(power/samples.size()),"mean_original_lr_difference":stereo_difference/samples.size(),"envelope_rms_low":low,"envelope_rms_high":high,"intensity_min":minimum,"intensity_max":maximum,"keys":animation.track_get_key_count(track)}
	var file:=FileAccess.open(OUTPUT+"authoring_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("EMERGENCY ALARM AUTHORED ",JSON.stringify(report))
	quit()
