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
			final buildExit = Sys.command("dune", ["build", target]);
			if (buildExit != 0) {
				Sys.setCwd(prev);
				return cfg.strict
					? Err("dune build failed with exit code " + buildExit)
					: Ok("dune build failed with exit code " + buildExit + " (skipping)");
			} else {
				if (cfg.mli != null) {
					switch (cfg.mli) {
						case "infer":
							final mliRes = OcamlMliGenerator.tryInferFromBuild(outDirAbs);
							switch (mliRes) {
								case Ok(_):
									// Rebuild so dune validates the newly-written interfaces.
									final rebuildExit = Sys.command("dune", ["build", target]);
									if (rebuildExit != 0) {
										Sys.setCwd(prev);
										return cfg.mliStrict
											? Err("dune rebuild failed after generating .mli (exit code " + rebuildExit + ")")
											: Ok("dune rebuild failed after generating .mli (exit code " + rebuildExit + ") (skipping)");
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
											final rebuildExit = Sys.command("dune", ["build", target]);
											if (rebuildExit != 0) {
												Sys.setCwd(prev);
												return cfg.mliStrict
													? Err("dune rebuild failed after generating .mli (exit code " + rebuildExit + ")")
													: Ok("dune rebuild failed after generating .mli (exit code " + rebuildExit + ") (skipping)");
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
					final runExit = Sys.command("dune", ["exec", target]);
					if (runExit != 0) {
						Sys.setCwd(prev);
						return cfg.strict
							? Err("dune exec failed with exit code " + runExit)
							: Ok("dune exec failed with exit code " + runExit + " (skipping)");
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
