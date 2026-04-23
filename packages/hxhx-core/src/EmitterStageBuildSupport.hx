import haxe.io.Path;

/**
	OCaml build/link orchestration for `EmitterStage.emitToDir(...)`.

	Why
	- `EmitterStage` still owned the final native build/link path: canonicalizing
	  emitted `.ml` units, sorting them with `ocamldep`, and invoking `ocamlopt`.
	- That logic is build-support orchestration, not expression/statement lowering.

	What
	- Computes the expected Stage3 executable path.
	- Normalizes `.ml` unit paths for case-insensitive filesystems.
	- Orders units with `ocamldep -sort` and runs `ocamlopt`.

	How
	- Preserve the existing argv shape, warning-related include paths, and trace
	  phases used by the current build flow.
**/
class EmitterStageBuildSupport {
	static function uniqStrings(xs:Array<String>):Array<String> {
		if (xs == null || xs.length <= 1)
			return xs;
		final seen = new Map<String, Bool>();
		final out = new Array<String>();
		for (x in xs) {
			if (x == null)
				continue;
			if (seen.exists(x))
				continue;
			seen.set(x, true);
			out.push(x);
		}
		return out;
	}

	static function ocamldepSort(mlFiles:Array<String>):Array<String> {
		if (mlFiles == null || mlFiles.length <= 1)
			return mlFiles;

		final ocamldep = {
			final value = Sys.getEnv("OCAMLDEP");
			(value == null || value.length == 0) ? "ocamldep" : value;
		}

		final process = new sys.io.Process(ocamldep, [
			"-I",
			"runtime",
			"-I",
			"+unix",
			"-I",
			"+str",
			"-I",
			"+threads",
			"-I",
			"+dynlink",
			"-sort"
		].concat(mlFiles));
		final chunks = new Array<String>();
		try {
			while (true)
				chunks.push(process.stdout.readLine());
		} catch (_:haxe.io.Eof) {}

		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "stage3 emitter: ocamldep -sort failed with exit code " + code;

		final sorted = new Array<String>();
		for (chunk in chunks) {
			for (token in chunk.split(" ")) {
				final value = StringTools.trim(token);
				if (value.length == 0 || !StringTools.endsWith(value, ".ml"))
					continue;
				sorted.push(value);
			}
		}

		return sorted.length == 0 ? mlFiles : sorted;
	}

	public static inline function expectedExePath(outAbs:String):String {
		return Path.join([outAbs, "out.exe"]);
	}

	public static function buildNativeExecutable(outAbs:String, runtimePaths:Array<String>, generatedPaths:Array<String>, emittedModulePaths:Array<String>,
			rootMainPath:Null<String>):String {
		final exePath = expectedExePath(outAbs);
		try {
			if (sys.FileSystem.exists(exePath))
				sys.FileSystem.deleteFile(exePath);
		} catch (_:haxe.io.Error) {} catch (_:String) {}

		final ocamlopt = {
			final value = Sys.getEnv("OCAMLOPT");
			(value == null || value.length == 0) ? "ocamlopt" : value;
		}

		final prevCwd = try Sys.getCwd() catch (_:haxe.io.Error) null catch (_:String) null;
		if (prevCwd == null)
			throw "stage3 emitter: cannot read current working directory";
		Sys.setCwd(outAbs);

		inline function lowerKey(path:String):String {
			return path == null ? "" : path.toLowerCase();
		}

		final canonicalByLower:Map<String, String> = new Map();
		function registerCanonical(relPath:String):Void {
			if (relPath == null || relPath.length == 0)
				return;
			final key = lowerKey(relPath);
			if (canonicalByLower.exists(key)) {
				final prev = canonicalByLower.get(key);
				if (prev != relPath)
					throw "stage3 emitter: case-insensitive .ml collision: '" + prev + "' vs '" + relPath + "'";
				return;
			}
			canonicalByLower.set(key, relPath);
		}

		function scanMlDir(absDir:String, prefix:String):Void {
			if (absDir == null || absDir.length == 0)
				return;
			if (!sys.FileSystem.exists(absDir) || !sys.FileSystem.isDirectory(absDir))
				return;
			for (name in sys.FileSystem.readDirectory(absDir)) {
				if (name == null || !StringTools.endsWith(name, ".ml"))
					continue;
				registerCanonical(prefix.length == 0 ? name : (prefix + "/" + name));
			}
		}

		scanMlDir(outAbs, "");
		scanMlDir(Path.join([outAbs, "runtime"]), "runtime");
		var canonicalCount = 0;
		for (_ in canonicalByLower.keys())
			canonicalCount++;
		EmitterStageDebug.traceStage3Phase("after_scan_ml_dir:" + canonicalCount);

		function canonicalize(relPath:String):String {
			if (relPath == null || relPath.length == 0)
				return relPath;
			final key = lowerKey(relPath);
			return canonicalByLower.exists(key) ? canonicalByLower.get(key) : relPath;
		}

		function listExistingMlUnits():Array<String> {
			final out = new Array<String>();
			for (key in canonicalByLower.keys()) {
				final rel = canonicalByLower.get(key);
				if (rel == null || rel.length == 0)
					continue;
				final base = Path.withoutDirectory(rel);
				if (base == null || !StringTools.endsWith(base, ".ml"))
					continue;
				if (base == "out.ml")
					continue;
				out.push(canonicalize(rel));
			}
			out.sort(function(a:String, b:String):Int {
				return (a < b) ? -1 : ((a > b) ? 1 : 0);
			});
			return out;
		}

		function uniqCaseInsensitive(xs:Array<String>):Array<String> {
			if (xs == null || xs.length <= 1)
				return xs;
			final seen:Map<String, Bool> = new Map();
			final out = new Array<String>();
			for (x in xs) {
				if (x == null || x.length == 0)
					continue;
				final key = lowerKey(x);
				if (seen.exists(key))
					continue;
				seen.set(key, true);
				out.push(canonicalize(x));
			}
			return out;
		}

		final existingMl = listExistingMlUnits();
		final allMl = uniqCaseInsensitive(existingMl.concat(runtimePaths).concat(generatedPaths).concat(emittedModulePaths).map(canonicalize));
		EmitterStageDebug.traceStage3Phase("before_ocamldep_sort:" + allMl.length);
		final orderedMl = uniqCaseInsensitive(ocamldepSort(allMl).map(canonicalize));
		EmitterStageDebug.traceStage3Phase("after_ocamldep_sort:" + orderedMl.length);

		final orderedNoRoot = new Array<String>();
		for (path in orderedMl)
			if (rootMainPath == null || path != rootMainPath)
				orderedNoRoot.push(path);
		if (rootMainPath != null)
			orderedNoRoot.push(rootMainPath);
		final orderedNoRootUniq = uniqStrings(orderedNoRoot);
		EmitterStageDebug.traceStage3Phase("after_ordered_units:" + orderedNoRootUniq.length);

		final args = new Array<String>();
		args.push("-I");
		args.push("+unix");
		args.push("-I");
		args.push("+str");
		args.push("-I");
		args.push("+threads");
		args.push("-I");
		args.push("+dynlink");
		args.push("-I");
		args.push("runtime");
		args.push("-o");
		args.push("out.exe");
		args.push("-thread");
		args.push("unix.cmxa");
		args.push("threads.cmxa");
		args.push("str.cmxa");
		args.push("dynlink.cmxa");
		for (path in orderedNoRootUniq)
			args.push(path);
		EmitterStageDebug.traceStage3Phase("before_ocamlopt:" + args.length);

		final code = try {
			Sys.command(ocamlopt, args);
		} catch (error:haxe.io.Error) {
			Sys.setCwd(prevCwd);
			EmitterStageDebug.traceStage3Phase("ocamlopt_io_error");
			throw error;
		} catch (error:String) {
			Sys.setCwd(prevCwd);
			EmitterStageDebug.traceStage3Phase("ocamlopt_string_error");
			throw error;
		};
		Sys.setCwd(prevCwd);
		EmitterStageDebug.traceStage3Phase("after_ocamlopt:" + code);
		if (code != 0)
			throw "stage3 emitter: ocamlopt failed with exit code " + code;
		EmitterStageDebug.traceStage3Phase("before_missing_exe_check");
		if (!sys.FileSystem.exists(exePath))
			throw "stage3 emitter: missing built executable: " + exePath;
		EmitterStageDebug.traceStage3Phase("after_missing_exe_check");
		return exePath;
	}
}
