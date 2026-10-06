extends SceneTree
## Headless test runner. Use tools/test.sh rather than calling this directly.
## Runs every tests/unit/test_*.gd then tests/integration/test_*.gd.
## User args after `--` filter test files by substring.

const DIRS := ["res://tests/unit", "res://tests/integration"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filters: Array = Array(OS.get_cmdline_user_args())
	var files: Array[String] = []
	for dir in DIRS:
		for file in DirAccess.get_files_at(dir):
			if file.begins_with("test_") and file.ends_with(".gd"):
				var path: String = dir.path_join(file)
				if filters.is_empty() or filters.any(func(f: String) -> bool: return path.contains(f)):
					files.append(path)

	var passed := 0
	var failed := 0
	var failures: Array[String] = []
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			failures.append("%s: failed to load" % path)
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.tree = self
			await test.before_each()
			await test.call(name)
			await test.after_each()
			if test._failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in test._failures:
					failures.append("%s::%s  %s" % [path.get_file(), name, f])

	for f in failures:
		printerr("FAIL ", f)
	print("\n%d passed, %d failed (%d files)" % [passed, failed, files.size()])
	quit(1 if failed > 0 or files.is_empty() else 0)
