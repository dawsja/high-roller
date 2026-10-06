class_name NetLog
extends RefCounted
## One greppable stdout line per network event, for `--net-log` and
## tools/net_test.sh: `NET pid=<this peer> t=<seconds> <event> key=value ...`.
## Off by default; nothing is formatted while it is off.

static var enabled: bool = false
## This peer's pid (0 until it is known).
static var pid: int = 0


static func line(event: String, fields: Dictionary = {}) -> void:
	if not enabled:
		return
	var parts: PackedStringArray = ["NET", "pid=%d" % pid, "t=%.2f" % (Time.get_ticks_msec() / 1000.0), event]
	for key: Variant in fields:
		parts.append("%s=%s" % [str(key), _value(fields[key])])
	print(" ".join(parts))


static func _value(v: Variant) -> String:
	if v is float:
		return "%.3f" % float(v)
	if v is Vector3:
		var p: Vector3 = v
		return "%.2f,%.2f,%.2f" % [p.x, p.y, p.z]
	if v is Array or v is PackedInt32Array:
		var items: PackedStringArray = []
		for item: Variant in v:
			items.append(str(item))
		return ",".join(items)
	return str(v).replace(" ", "_")
