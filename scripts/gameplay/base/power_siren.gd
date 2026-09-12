extends RefCounted

static func make_stream() -> AudioStreamWAV:
	var rate := 22050
	var samples := PackedByteArray()
	samples.resize(rate * 2 * 2)
	var phase := 0.0
	for i in rate * 2:
		var t := float(i) / rate
		phase += TAU * (560.0 + 210.0 * sin(TAU * t / 2.0)) / rate
		var sample := int(sin(phase) * 15000.0)
		samples.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = samples
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = rate * 2
	return wav
