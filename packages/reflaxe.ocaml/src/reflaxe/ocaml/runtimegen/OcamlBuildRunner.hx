package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import reflaxe.ocaml.runtimegen.OcamlBuildTimingReport.OcamlBuildTimingPhase;
import reflaxe.ocaml.runtimegen.OcamlBuildTimingReport.OcamlBuildTimingReportWriter;

enum BuildResult {
	Ok(msg:Null<String>);
	Err(msg:String);
}

typedef BuildRunConfig = {
	final outDir:String;
	final exeName:String;
	final mode:String; // "native" | "byte"
	final duneLayout:Null<String>;
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

	/** Writes target-owned Dune phase timings tied to the current generated receipt. **/
	final timingReport:Bool;
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

	static function isLibraryLayout(duneLayout:Null<String>):Bool {
		return duneLayout == "lib" || duneLayout == "library";
	}

	static function duneTarget(exeName:String, mode:String, duneLayout:Null<String>):String {
		if (isLibraryLayout(duneLayout)) {
			return "@all";
		}
		final ext = (mode == "byte" || mode == "bytecode") ? "bc" : "exe";
		return "./" + exeName + "." + ext;
	}

	static function builtExePath(exeName:String, mode:String):String {
		final ext = (mode == "byte" || mode == "bytecode") ? "bc" : "exe";
		return Path.join(["_build", "default", exeName + "." + ext]);
	}

	static function shellQuote(s:String):String {
		if (s == null)
			return "''";
		// POSIX shell single-quote escaping: ' -> '\'' .
		return "'" + s.split("'").join("'\\''") + "'";
	}

	static function truncateOutput(out:String):String {
		if (out == null)
			return "";
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

	static function runCapture(cmd:String, args:Array<String>):{code:Int, output:String, elapsedMilliseconds:Int} {
		final started = haxe.Timer.stamp();
		final isWindows = Sys.systemName() == "Windows";
		if (isWindows) {
			// Best-effort on Windows: avoid complex quoting; fall back to no capture.
			final code = Sys.command(cmd, args);
			return {code: code, output: "", elapsedMilliseconds: elapsedMilliseconds(started)};
		}

		final full = ([cmd].concat(args)).map(shellQuote).join(" ");
		final p = new sys.io.Process("sh", ["-lc", full + " 2>&1"]);
		final output = p.stdout.readAll().toString();
		final code = p.exitCode();
		p.close();
		return {code: code, output: output, elapsedMilliseconds: elapsedMilliseconds(started)};
	}

	static function elapsedMilliseconds(started:Float):Int {
		return Math.round(Math.max(0.0, (haxe.Timer.stamp() - started) * 1000.0));
	}

	static function normalizedLayout(duneLayout:Null<String>):String {
		return isLibraryLayout(duneLayout) ? "library" : (duneLayout == "plugin" ? "plugin" : "executable");
	}

	public static function tryBuildAndMaybeRun(cfg:BuildRunConfig):BuildResult {
		final mode = cfg.mode == null ? "native" : cfg.mode;
		final outDir = cfg.outDir;
		final libraryLayout = isLibraryLayout(cfg.duneLayout);
		final target = duneTarget(cfg.exeName, mode, cfg.duneLayout);
		final phases = new Array<OcamlBuildTimingPhase>();

		function addPhase(id:String, elapsed:Int, exitCode:Int):Void {
			phases.push({id: id, elapsedMilliseconds: elapsed, exitCode: exitCode});
		}

		function finish(result:BuildResult, status:String, exitCode:Int):BuildResult {
			if (!cfg.timingReport) {
				return result;
			}

			var nativeBuildRan = false;
			var duneBuildMilliseconds = 0;
			var interfaceMilliseconds = 0;
			var targetRunMilliseconds:Null<Int> = null;
			for (phase in phases) {
				if (phase.id == "dune_build" || phase.id == "mli_rebuild") {
					nativeBuildRan = true;
					duneBuildMilliseconds += phase.elapsedMilliseconds;
				} else if (phase.id.indexOf("mli_") == 0) {
					interfaceMilliseconds += phase.elapsedMilliseconds;
				} else if (phase.id == "dune_exec") {
					targetRunMilliseconds = phase.elapsedMilliseconds;
				}
			}

			try {
				OcamlBuildTimingReportWriter.write(outDir, mode, normalizedLayout(cfg.duneLayout), target, cfg.strict, cfg.run, cfg.mli, phases, {
					status: status,
					exitCode: exitCode,
					nativeBuildRan: nativeBuildRan,
					duneBuildMilliseconds: nativeBuildRan ? duneBuildMilliseconds : null,
					interfaceMilliseconds: interfaceMilliseconds,
					targetRunMilliseconds: targetRunMilliseconds
				});
				return result;
			} catch (error:Dynamic) {
				final reportError = "Could not write OCaml native timing report: " + Std.string(error);
				return switch (result) {
					case Err(message): Err(message + "\n\n" + reportError);
					case Ok(_): Err(reportError);
				};
			}
		}

		if (libraryLayout && cfg.run) {
			return
				finish(Err("ocaml_run cannot execute a library-only Dune layout. Build the library without -D ocaml_run, then consume it from an OCaml executable."),
				"failed", 2);
		}

		final toolchainStarted = haxe.Timer.stamp();
		final hasNativeToolchain = hasCommand("dune") && hasCommand("ocamlc");
		addPhase("native_toolchain_probe", elapsedMilliseconds(toolchainStarted), hasNativeToolchain ? 0 : 127);
		if (!hasNativeToolchain) {
			return finish(cfg.strict ? Err("dune/ocamlc not found on PATH (required by ocaml_build/ocaml_mli).") : Ok(null), "failed", 127);
		}
		if (cfg.mli != null) {
			final interfaceProbeStarted = haxe.Timer.stamp();
			final hasInterfaceToolchain = hasOcamlfind();
			addPhase("mli_toolchain_probe", elapsedMilliseconds(interfaceProbeStarted), hasInterfaceToolchain ? 0 : 127);
			if (!hasInterfaceToolchain) {
				return finish(cfg.mliStrict ? Err("ocaml_mli requested but ocamlfind not found on PATH.") : Ok(null), "failed", 127);
			}
		}

		final prev = Sys.getCwd();
		final notes:Array<String> = [];
		var changedDirectory = false;
		try {
			Sys.setCwd(outDir);
			changedDirectory = true;
			final outDirAbs = Sys.getCwd();
			// IMPORTANT:
			// When the OCaml output directory lives *inside* another dune workspace (e.g. inside the
			// upstream Haxe repo, which contains its own `dune-project` / `dune-workspace.*`),
			// dune will otherwise “walk up” and treat the outer workspace as the project root.
			//
			// Force the root to the generated output directory so Gate runners can nest outputs
			// without colliding with upstream's own dune config.
			final duneRoot = outDirAbs;
			final buildRes = runCapture("dune", ["build", "--root", duneRoot, target]);
			addPhase("dune_build", buildRes.elapsedMilliseconds, buildRes.code);
			if (buildRes.code != 0) {
				final out = truncateOutput(buildRes.output);
				Sys.setCwd(prev);
				changedDirectory = false;
				return finish(cfg.strict ? Err("dune build failed (exit " + buildRes.code + ")\n\n" + out) : Ok("dune build failed (exit " + buildRes.code
					+ ") (skipping)\n\n" + out),
					"failed", buildRes.code);
			} else {
				if (cfg.mli != null) {
					switch (cfg.mli) {
						case "infer":
							final inferStarted = haxe.Timer.stamp();
							final mliRes = OcamlMliGenerator.tryInferFromBuild(outDirAbs);
							addPhase("mli_infer", elapsedMilliseconds(inferStarted), switch (mliRes) {
								case Ok(_): 0;
								case Err(_): 1;
							});
							switch (mliRes) {
								case Ok(_):
									// Rebuild so dune validates the newly-written interfaces.
									final rebuildRes = runCapture("dune", ["build", "--root", duneRoot, target]);
									addPhase("mli_rebuild", rebuildRes.elapsedMilliseconds, rebuildRes.code);
									if (rebuildRes.code != 0) {
										final out = truncateOutput(rebuildRes.output);
										Sys.setCwd(prev);
										changedDirectory = false;
										return finish(cfg.mliStrict ? Err("dune rebuild failed after generating .mli (exit " + rebuildRes.code + ")\n\n" +
											out) : Ok("dune rebuild failed after generating .mli (exit "
											+ rebuildRes.code + ") (skipping)\n\n" + out),
											"failed", rebuildRes.code);
									}
								case Err(msg):
									Sys.setCwd(prev);
									changedDirectory = false;
									return finish(cfg.mliStrict ? Err(msg) : Ok(msg + " (skipping)"), "failed", 1);
							}
						case "all":
							// A library @all build already compiles every library module. The
							// executable layout needs its historical explicit CMI closure.
							final ensureRes = if (libraryLayout) {
								Ok(null);
							} else {
								final ensureStarted = haxe.Timer.stamp();
								final result = OcamlMliGenerator.tryEnsureAllCmiBuilt({
									outDir: outDirAbs,
									exeName: cfg.exeName,
									mode: mode
								});
								addPhase("mli_ensure", elapsedMilliseconds(ensureStarted), switch (result) {
									case Ok(_): 0;
									case Err(_): 1;
								});
								result;
							};
							switch (ensureRes) {
								case Ok(_):
									final inferStarted = haxe.Timer.stamp();
									final mliRes = OcamlMliGenerator.tryInferFromBuild(outDirAbs);
									addPhase("mli_infer", elapsedMilliseconds(inferStarted), switch (mliRes) {
										case Ok(_): 0;
										case Err(_): 1;
									});
									switch (mliRes) {
										case Ok(_):
											final rebuildRes = runCapture("dune", ["build", "--root", duneRoot, target]);
											addPhase("mli_rebuild", rebuildRes.elapsedMilliseconds, rebuildRes.code);
											if (rebuildRes.code != 0) {
												final out = truncateOutput(rebuildRes.output);
												Sys.setCwd(prev);
												changedDirectory = false;
												return finish(cfg.mliStrict ? Err("dune rebuild failed after generating .mli (exit " + rebuildRes.code
													+ ")\n\n" + out) : Ok("dune rebuild failed after generating .mli (exit " + rebuildRes.code
														+ ") (skipping)\n\n" + out),
													"failed", rebuildRes.code);
											}
										case Err(msg):
											Sys.setCwd(prev);
											changedDirectory = false;
											return finish(cfg.mliStrict ? Err(msg) : Ok(msg + " (skipping)"), "failed", 1);
									}
								case Err(msg):
									Sys.setCwd(prev);
									changedDirectory = false;
									return finish(cfg.mliStrict ? Err(msg) : Ok(msg + " (skipping)"), "failed", 1);
							}
						case other:
							Sys.setCwd(prev);
							changedDirectory = false;
							return finish(cfg.mliStrict ? Err("Unknown ocaml_mli mode: " + other + " (expected: infer|all)") : Ok("Unknown ocaml_mli mode: "
								+ other + " (skipping)"),
								"failed", 2);
					}
				}

				if (cfg.run) {
					final runRes = runCapture("dune", ["exec", "--root", duneRoot, target]);
					addPhase("dune_exec", runRes.elapsedMilliseconds, runRes.code);
					if (runRes.code != 0) {
						final out = truncateOutput(runRes.output);
						Sys.setCwd(prev);
						changedDirectory = false;
						return finish(cfg.strict ? Err("dune exec failed (exit " + runRes.code + ")\n\n" + out) : Ok("dune exec failed (exit " + runRes.code
							+ ") (skipping)\n\n" + out),
							"failed", runRes.code);
					} else {
						notes.push("Built OCaml output via dune: " + target);
					}
				} else {
					notes.push("Built OCaml output via dune: " + target);
				}
			}
		} catch (e:Dynamic) {
			if (changedDirectory) {
				Sys.setCwd(prev);
				changedDirectory = false;
			}
			return finish(cfg.strict ? Err("OCaml build step failed: " + Std.string(e)) : Ok(null), "failed", 1);
		}
		Sys.setCwd(prev);
		changedDirectory = false;
		return finish(Ok(notes.length > 0 ? notes.join("\n") : null), "passed", 0);
	}
}
#end
