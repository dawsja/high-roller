extends TestCase
## Co-op over real sockets: runs tools/net_test.sh with one client (a
## headless host and a headless client on localhost, both playing the
## scripted NetBot) and fails if any of its checks fail. Skips, with a
## message, where the environment can't open a UDP socket on localhost.
## Takes about a minute.


func test_host_and_one_client_over_localhost() -> void:
	var script_path := ProjectSettings.globalize_path("res://tools/net_test.sh")
	if OS.get_name() == "Windows" or not FileAccess.file_exists(script_path):
		print("SKIP test_net_two_process: needs bash and tools/net_test.sh")
		return
	var godot := OS.get_executable_path()
	var command := "GODOT='%s' bash '%s' 1" % [godot.replace("'", "'\\''"), script_path.replace("'", "'\\''")]
	var out: Array = []
	var code := OS.execute("bash", ["-c", command], out, true)
	var lines: PackedStringArray = "\n".join(out).split("\n")
	if code == 77:
		print("SKIP test_net_two_process: no UDP socket on localhost here (net_test.sh exit 77)")
		return
	var checks := 0
	for line: String in lines:
		if line.begins_with("  ok") or line.begins_with("  FAIL") or line.begins_with("net_test.sh:"):
			print(line)
			if line.begins_with("  ok"):
				checks += 1
	if code != 0:
		# The peers' own error lines (already in the output above) fail the run too.
		for line: String in lines:
			if line.begins_with("NET ") or line.begins_with("---"):
				print(line)
	assert_eq(code, 0, "tools/net_test.sh 1 passed")
	assert_gt(checks, 20.0, "net_test.sh ran its checks")
