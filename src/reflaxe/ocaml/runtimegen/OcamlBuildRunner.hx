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
				? Err("ocaml_build requested but dune/ocamlc not found on PATH.")
				: Ok(null);
		}

		final prev = Sys.getCwd();
		Sys.setCwd(outDir);
		var result:BuildResult = Ok(null);
		try {
			final target = duneTarget(cfg.exeName, mode);
			final buildExit = Sys.command("dune", ["build", target]);
			if (buildExit != 0) {
				result = cfg.strict
					? Err("dune build failed with exit code " + buildExit)
					: Ok("dune build failed with exit code " + buildExit + " (skipping)");
			} else {
				if (cfg.run) {
					final runExit = Sys.command("dune", ["exec", target]);
					if (runExit != 0) {
						result = cfg.strict
							? Err("dune exec failed with exit code " + runExit)
							: Ok("dune exec failed with exit code " + runExit + " (skipping)");
					} else {
						result = Ok("Built OCaml output via dune: " + target);
					}
				} else {
					result = Ok("Built OCaml output via dune: " + target);
				}
			}
		} catch (e:Dynamic) {
			result = cfg.strict
				? Err("OCaml build step failed: " + Std.string(e))
				: Ok(null);
		}
		Sys.setCwd(prev);
		return result;
	}
}

#end
