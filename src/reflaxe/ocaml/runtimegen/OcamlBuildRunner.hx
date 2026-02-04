package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)

import haxe.io.Path;

enum BuildResult {
	Ok(msg:Null<String>);
	Err(msg:String);
}

typedef BuildRunConfig = {
	final outDir:String;
	final exeName:String;
	final mode:String; // "native" | "byte"
	final run:Bool;
	final strict:Bool;
	/**
		If set, the backend will attempt to emit `*.mli` interface files after
		a successful dune build.

		Supported values:

		- `"infer"`: infer interfaces via `ocamlc -i` (recommended).

		Other values are reserved for future modes (e.g. curated public APIs).
	**/
	final mli:Null<String>;

	/**
		If true, failures in the `.mli` generation step are treated as hard errors.
	**/
	final mliStrict:Bool;
}

class OcamlBuildRunner {
	static inline final MAX_ERROR_OUTPUT_CHARS = 16000;
	static inline final MAX_ERROR_OUTPUT_LINES = 250;

	static function hasCommand(cmd:String):Bool {
		try {
			final p = new sys.io.Process(cmd, ["--version"]);
			final code = p.exitCode();
			p.close();
			return code == 0;
		} catch (_) {
			return false;
		}
	}

	static function hasOcamlfind():Bool {
		try {
			final p = new sys.io.Process("ocamlfind", ["list"]);
			final code = p.exitCode();
			p.close();
			return code == 0;
		} catch (_) {
			return false;
		}
	}

	static function duneTarget(exeName:String, mode:String):String {
		final ext = (mode == "byte" || mode == "bytecode") ? "bc" : "exe";
		return "./" + exeName + "." + ext;
	}

	static function builtExePath(exeName:String, mode:String):String {
		final ext = (mode == "byte" || mode == "bytecode") ? "bc" : "exe";
		return Path.join(["_build", "default", exeName + "." + ext]);
	}

	static function shellQuote(s:String):String {
		if (s == null) return "''";
		// POSIX shell single-quote escaping: ' -> '\'' .
		return "'" + s.split("'").join("'\\''") + "'";
	}

	static function truncateOutput(out:String):String {
		if (out == null) return "";
		var s = out;
		final lines = s.split("\n");
		if (lines.length > MAX_ERROR_OUTPUT_LINES) {
			s = lines.slice(lines.length - MAX_ERROR_OUTPUT_LINES).join("\n");
		}
		if (s.length > MAX_ERROR_OUTPUT_CHARS) {
			s = s.substr(s.length - MAX_ERROR_OUTPUT_CHARS);
		}
		return s;
	}

	static function runCapture(cmd:String, args:Array<String>):{ code:Int, output:String } {
		final isWindows = Sys.systemName() == "Windows";
		if (isWindows) {
			// Best-effort on Windows: avoid complex quoting; fall back to no capture.
			final code = Sys.command(cmd, args);
			return { code: code, output: "" };
		}

		final full = ([cmd].concat(args)).map(shellQuote).join(" ");
		final p = new sys.io.Process("sh", ["-lc", full + " 2>&1"]);
		final output = p.stdout.readAll().toString();
		final code = p.exitCode();
		p.close();
		return { code: code, output: output };
	}

	public static function tryBuildAndMaybeRun(cfg:BuildRunConfig):BuildResult {
		final mode = cfg.mode == null ? "native" : cfg.mode;
		final outDir = cfg.outDir;

		if (!hasCommand("dune") || !hasCommand("ocamlc")) {
			return cfg.strict
				? Err("dune/ocamlc not found on PATH (required by ocaml_build/ocaml_mli).")
				: Ok(null);
		}
		if (cfg.mli != null && !hasOcamlfind()) {
			return cfg.mliStrict
				? Err("ocaml_mli requested but ocamlfind not found on PATH.")
				: Ok(null);
		}

		final prev = Sys.getCwd();
		Sys.setCwd(outDir);
		final outDirAbs = Sys.getCwd();
		final notes:Array<String> = [];
		try {
			final target = duneTarget(cfg.exeName, mode);
			final buildRes = runCapture("dune", ["build", target]);
			if (buildRes.code != 0) {
				final out = truncateOutput(buildRes.output);
				Sys.setCwd(prev);
				return cfg.strict
					? Err("dune build failed (exit " + buildRes.code + ")\n\n" + out)
					: Ok("dune build failed (exit " + buildRes.code + ") (skipping)\n\n" + out);
			} else {
				if (cfg.mli != null) {
					switch (cfg.mli) {
						case "infer":
							final mliRes = OcamlMliGenerator.tryInferFromBuild(outDirAbs);
							switch (mliRes) {
								case Ok(_):
									// Rebuild so dune validates the newly-written interfaces.
									final rebuildRes = runCapture("dune", ["build", target]);
									if (rebuildRes.code != 0) {
										final out = truncateOutput(rebuildRes.output);
										Sys.setCwd(prev);
										return cfg.mliStrict
											? Err("dune rebuild failed after generating .mli (exit " + rebuildRes.code + ")\n\n" + out)
											: Ok("dune rebuild failed after generating .mli (exit " + rebuildRes.code + ") (skipping)\n\n" + out);
									}
								case Err(msg):
									Sys.setCwd(prev);
									return cfg.mliStrict ? Err(msg) : Ok(msg + " (skipping)");
							}
						case "all":
							final ensureRes = OcamlMliGenerator.tryEnsureAllCmiBuilt({
								outDir: outDirAbs,
								exeName: cfg.exeName,
								mode: mode
							});
							switch (ensureRes) {
								case Ok(_):
									final mliRes = OcamlMliGenerator.tryInferFromBuild(outDirAbs);
									switch (mliRes) {
										case Ok(_):
											final rebuildRes = runCapture("dune", ["build", target]);
											if (rebuildRes.code != 0) {
												final out = truncateOutput(rebuildRes.output);
												Sys.setCwd(prev);
												return cfg.mliStrict
													? Err("dune rebuild failed after generating .mli (exit " + rebuildRes.code + ")\n\n" + out)
													: Ok("dune rebuild failed after generating .mli (exit " + rebuildRes.code + ") (skipping)\n\n" + out);
											}
										case Err(msg):
											Sys.setCwd(prev);
											return cfg.mliStrict ? Err(msg) : Ok(msg + " (skipping)");
									}
								case Err(msg):
									Sys.setCwd(prev);
									return cfg.mliStrict ? Err(msg) : Ok(msg + " (skipping)");
							}
						case other:
							Sys.setCwd(prev);
							return cfg.mliStrict
								? Err("Unknown ocaml_mli mode: " + other + " (expected: infer|all)")
								: Ok("Unknown ocaml_mli mode: " + other + " (skipping)");
					}
				}

				if (cfg.run) {
					final runRes = runCapture("dune", ["exec", target]);
					if (runRes.code != 0) {
						final out = truncateOutput(runRes.output);
						Sys.setCwd(prev);
						return cfg.strict
							? Err("dune exec failed (exit " + runRes.code + ")\n\n" + out)
							: Ok("dune exec failed (exit " + runRes.code + ") (skipping)\n\n" + out);
					} else {
						notes.push("Built OCaml output via dune: " + target);
					}
				} else {
					notes.push("Built OCaml output via dune: " + target);
				}
			}
		} catch (e:Dynamic) {
			Sys.setCwd(prev);
			return cfg.strict
				? Err("OCaml build step failed: " + Std.string(e))
				: Ok(null);
		}
		Sys.setCwd(prev);
		return Ok(notes.length > 0 ? notes.join("\n") : null);
	}
}

#end
