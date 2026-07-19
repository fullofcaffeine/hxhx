package reflaxe.ocaml.tooling;

import haxe.io.Path;

using StringTools;

/**
	Runs the safe reflaxe.ocaml edit/build/test loop.

	Each rebuild starts a fresh Haxe process. Reflaxe keeps unchanged generated
	files untouched, allowing Dune to reuse its native build cache when the project
	invokes it. The watcher deliberately avoids a persistent Haxe server because
	incomplete Reflaxe output has been observed under server reuse in this
	repository.
**/
class ReflaxeOcamlAuthoring {
	static final IGNORED_DIRECTORIES = [".artifacts", ".git", ".haxelib", ".lix", ".tmp", "_build", "node_modules"];
	static final WATCHED_EXTENSIONS = ["c", "h", "hx", "hxml", "json", "lock", "ml", "mli", "opam"];
	static final STANDARD_NATIVE_DIRECTORIES = ["adapters", "bindings", "native", "ocaml"];

	/** Runs one build, or keeps rebuilding stable input batches when watch is enabled. **/
	public static function run(host:AuthoringHost, projectRoot:String, options:AuthoringBuildOptions):Int {
		final resolvedProjectRoot = resolvePath(host, host.absolutePath("."), projectRoot);
		if (!host.isDirectory(resolvedProjectRoot)) {
			host.writeStderr('Project directory does not exist: $resolvedProjectRoot\n');
			return 2;
		}

		final hxmlPath = resolvePath(host, resolvedProjectRoot, options.hxmlPath);
		if (!host.exists(hxmlPath) || host.isDirectory(hxmlPath)) {
			host.writeStderr('HXML file does not exist: ${displayPath(resolvedProjectRoot, hxmlPath)}\n');
			return 2;
		}

		var buildCount = 0;
		var lastExitCode = runBuild(host, resolvedProjectRoot, hxmlPath, options, ++buildCount);
		if (!options.watch || reachedBuildLimit(options.maxBuilds, buildCount)) {
			return lastExitCode;
		}

		var watchRoots = discoverWatchRoots(host, resolvedProjectRoot, hxmlPath, options.watchPaths);
		if (!containsDirectory(host, watchRoots)) {
			host.writeStderr("No source directory was found to watch. Add a class path to the HXML or pass --watch-path <directory>.\n");
			return 2;
		}
		printWatchStart(host, resolvedProjectRoot, watchRoots, options);
		var previous = snapshot(host, watchRoots);

		while (!reachedBuildLimit(options.maxBuilds, buildCount)) {
			host.sleep(options.pollMilliseconds);
			var pending = snapshot(host, watchRoots);
			if (snapshotsEqual(previous, pending)) {
				continue;
			}

			pending = stableSnapshot(host, watchRoots, pending, options.debounceMilliseconds);
			final changed = changedPaths(previous, pending);
			printChanged(host, resolvedProjectRoot, changed);
			lastExitCode = runBuild(host, resolvedProjectRoot, hxmlPath, options, ++buildCount);

			// HXML changes may add or remove source roots. Re-discover after the
			// compiler settles, then take the baseline after generated files exist.
			watchRoots = discoverWatchRoots(host, resolvedProjectRoot, hxmlPath, options.watchPaths);
			if (!containsDirectory(host, watchRoots)) {
				host.writeStderr("No source directory remains available to watch.\n");
				return 2;
			}
			previous = snapshot(host, watchRoots);
		}

		return lastExitCode;
	}

	static function runBuild(host:AuthoringHost, projectRoot:String, hxmlPath:String, options:AuthoringBuildOptions, buildNumber:Int):Int {
		final displayedHxml = displayPath(projectRoot, hxmlPath);
		host.writeStdout('[reflaxe.ocaml] build #$buildNumber: haxe $displayedHxml\n');
		final started = host.nowMilliseconds();
		final haxeExitCode = host.run("haxe", [hxmlPath], projectRoot);
		final elapsed = elapsedMilliseconds(host, started);
		if (haxeExitCode != 0) {
			host.writeStderr('[reflaxe.ocaml] build #$buildNumber failed (exit $haxeExitCode, ${elapsed}ms). Waiting for the next edit is safe in watch mode.\n');
			host.writeStdout('REFLAXE_OCAML_BUILD:FAIL builds=$buildNumber elapsed_ms=$elapsed exit_code=$haxeExitCode\n');
			return haxeExitCode;
		}

		host.writeStdout('[reflaxe.ocaml] build #$buildNumber passed in ${elapsed}ms.\n');
		host.writeStdout('REFLAXE_OCAML_BUILD:PASS builds=$buildNumber elapsed_ms=$elapsed\n');
		if (options.runArtifact == null) {
			return 0;
		}

		final artifact = resolvePath(host, projectRoot, options.runArtifact);
		if (!host.exists(artifact) || host.isDirectory(artifact)) {
			host.writeStderr('Built artifact does not exist: ${displayPath(projectRoot, artifact)}\n');
			return 2;
		}
		final runStarted = host.nowMilliseconds();
		final runExitCode = host.run(artifact, options.runArguments, projectRoot);
		final runElapsed = elapsedMilliseconds(host, runStarted);
		if (runExitCode != 0) {
			host.writeStderr('[reflaxe.ocaml] run failed (exit $runExitCode, ${runElapsed}ms).\n');
			host.writeStdout('REFLAXE_OCAML_RUN:FAIL elapsed_ms=$runElapsed exit_code=$runExitCode\n');
			return runExitCode;
		}
		host.writeStdout('[reflaxe.ocaml] run passed in ${runElapsed}ms.\n');
		host.writeStdout('REFLAXE_OCAML_RUN:PASS elapsed_ms=$runElapsed\n');
		return 0;
	}

	static function discoverWatchRoots(host:AuthoringHost, projectRoot:String, hxmlPath:String, explicitPaths:Array<String>):Array<String> {
		final roots:Map<String, Bool> = [];
		final visitedHxml:Map<String, Bool> = [];
		addHxmlRoots(host, projectRoot, hxmlPath, roots, visitedHxml);
		for (directory in STANDARD_NATIVE_DIRECTORIES) {
			final candidate = resolvePath(host, projectRoot, directory);
			if (host.isDirectory(candidate)) {
				roots.set(candidate, true);
			}
		}
		for (relative in explicitPaths) {
			final candidate = resolvePath(host, projectRoot, relative);
			if (host.exists(candidate)) {
				roots.set(candidate, true);
			} else {
				host.writeStderr('Watch path does not exist and will be ignored: ${displayPath(projectRoot, candidate)}\n');
			}
		}
		for (file in ["dune", "dune-project", "haxelib.json"]) {
			final candidate = resolvePath(host, projectRoot, file);
			if (host.exists(candidate) && !host.isDirectory(candidate)) {
				roots.set(candidate, true);
			}
		}
		final result = [for (root in roots.keys()) root];
		result.sort(compareStrings);
		return result;
	}

	static function addHxmlRoots(host:AuthoringHost, projectRoot:String, hxmlPath:String, roots:Map<String, Bool>, visited:Map<String, Bool>):Void {
		if (visited.exists(hxmlPath)) {
			return;
		}
		visited.set(hxmlPath, true);
		roots.set(hxmlPath, true);
		final contents = host.readFile(hxmlPath);
		if (contents == null) {
			return;
		}
		final classPathPattern = ~/^(?:-cp|--class-path)(?:=|\s+)(.+)$/;
		for (rawLine in contents.split("\n")) {
			final line = rawLine.trim();
			if (line.length == 0 || line.startsWith("#")) {
				continue;
			}
			if (classPathPattern.match(line)) {
				final classPath = resolvePath(host, projectRoot, unquote(classPathPattern.matched(1).trim()));
				if (host.isDirectory(classPath)) {
					roots.set(classPath, true);
				}
				continue;
			}
			if (!line.startsWith("-") && line.endsWith(".hxml")) {
				final included = resolvePath(host, projectRoot, unquote(line));
				if (host.exists(included) && !host.isDirectory(included)) {
					addHxmlRoots(host, projectRoot, included, roots, visited);
				}
			}
		}
	}

	static function snapshot(host:AuthoringHost, roots:Array<String>):Map<String, String> {
		final result:Map<String, String> = [];
		final visitedDirectories:Map<String, Bool> = [];
		for (root in roots) {
			collectSnapshot(host, root, result, visitedDirectories, true);
		}
		return result;
	}

	static function collectSnapshot(host:AuthoringHost, path:String, result:Map<String, String>, visitedDirectories:Map<String, Bool>, isRoot:Bool):Void {
		if (!host.exists(path)) {
			return;
		}
		if (!host.isDirectory(path)) {
			if (isRoot || isWatchedFile(path)) {
				addFileStamp(host, path, result);
			}
			return;
		}
		if (visitedDirectories.exists(path)) {
			return;
		}
		visitedDirectories.set(path, true);
		for (entry in host.readDirectory(path)) {
			final child = resolvePath(host, path, entry);
			if (host.isDirectory(child) && isIgnoredDirectory(entry)) {
				continue;
			}
			collectSnapshot(host, child, result, visitedDirectories, false);
		}
	}

	static function addFileStamp(host:AuthoringHost, path:String, result:Map<String, String>):Void {
		final value = host.stat(path);
		if (value != null) {
			result.set(path, '${value.modifiedMilliseconds}:${value.size}');
		}
	}

	static function stableSnapshot(host:AuthoringHost, roots:Array<String>, first:Map<String, String>, debounceMilliseconds:Int):Map<String, String> {
		var previous = first;
		while (true) {
			host.sleep(debounceMilliseconds);
			final current = snapshot(host, roots);
			if (snapshotsEqual(previous, current)) {
				return current;
			}
			previous = current;
		}
	}

	static function snapshotsEqual(left:Map<String, String>, right:Map<String, String>):Bool {
		final leftKeys = sortedKeys(left);
		final rightKeys = sortedKeys(right);
		if (leftKeys.length != rightKeys.length) {
			return false;
		}
		for (index in 0...leftKeys.length) {
			final leftKey = leftKeys[index];
			if (leftKey != rightKeys[index] || left.get(leftKey) != right.get(leftKey)) {
				return false;
			}
		}
		return true;
	}

	static function changedPaths(previous:Map<String, String>, current:Map<String, String>):Array<String> {
		final changed:Map<String, Bool> = [];
		for (path in previous.keys()) {
			if (!current.exists(path) || current.get(path) != previous.get(path)) {
				changed.set(path, true);
			}
		}
		for (path in current.keys()) {
			if (!previous.exists(path) || previous.get(path) != current.get(path)) {
				changed.set(path, true);
			}
		}
		final result = [for (path in changed.keys()) path];
		result.sort(compareStrings);
		return result;
	}

	static function printWatchStart(host:AuthoringHost, projectRoot:String, roots:Array<String>, options:AuthoringBuildOptions):Void {
		host.writeStdout('[reflaxe.ocaml] watching ${roots.length} input root${roots.length == 1 ? "" : "s"}; poll=${options.pollMilliseconds}ms debounce=${options.debounceMilliseconds}ms.\n');
		for (root in roots) {
			host.writeStdout('  - ${displayPath(projectRoot, root)}\n');
		}
		host.writeStdout("[reflaxe.ocaml] press Ctrl-C to stop. Each edit uses a fresh Haxe process; unchanged output preserves downstream build caches.\n");
	}

	static function printChanged(host:AuthoringHost, projectRoot:String, changed:Array<String>):Void {
		final shown = changed.slice(0, 8);
		host.writeStdout('[reflaxe.ocaml] ${changed.length} input${changed.length == 1 ? "" : "s"} changed: ${[for (path in shown) displayPath(projectRoot, path)].join(", ")}${changed.length > shown.length ? ", ..." : ""}\n');
	}

	static function isWatchedFile(path:String):Bool {
		final name = Path.withoutDirectory(path).toLowerCase();
		if (name == "dune" || name == "dune-project" || name.endsWith(".opam")) {
			return true;
		}
		return WATCHED_EXTENSIONS.contains(Path.extension(name));
	}

	static function isIgnoredDirectory(name:String):Bool {
		final normalized = name.toLowerCase();
		return IGNORED_DIRECTORIES.contains(normalized)
			|| normalized == "out"
			|| normalized.startsWith("out_")
			|| normalized.startsWith("out-");
	}

	static function containsDirectory(host:AuthoringHost, roots:Array<String>):Bool {
		for (root in roots) {
			if (host.isDirectory(root)) {
				return true;
			}
		}
		return false;
	}

	static function reachedBuildLimit(maxBuilds:Null<Int>, buildCount:Int):Bool {
		return maxBuilds != null && buildCount >= maxBuilds;
	}

	static function elapsedMilliseconds(host:AuthoringHost, started:Float):Int {
		return Math.round(Math.max(0.0, host.nowMilliseconds() - started));
	}

	static function sortedKeys(values:Map<String, String>):Array<String> {
		final result = [for (key in values.keys()) key];
		result.sort(compareStrings);
		return result;
	}

	static function resolvePath(host:AuthoringHost, base:String, path:String):String {
		return Path.normalize(host.absolutePath(Path.isAbsolute(path) ? path : Path.join([base, path])));
	}

	static function displayPath(projectRoot:String, path:String):String {
		final root = slashPath(Path.removeTrailingSlashes(projectRoot));
		final value = slashPath(path);
		final prefix = root + "/";
		return value.startsWith(prefix) ? value.substr(prefix.length) : value;
	}

	static function slashPath(path:String):String {
		return path.replace("\\", "/");
	}

	static function unquote(value:String):String {
		if (value.length >= 2) {
			final first = value.charAt(0);
			final last = value.charAt(value.length - 1);
			if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
				return value.substr(1, value.length - 2);
			}
		}
		return value;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
