package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)

import haxe.io.Path;

import reflaxe.ocaml.runtimegen.OcamlBuildRunner.BuildResult;

/**
	Generates OCaml `*.mli` interface files for emitted modules.

	Why this exists
	--------------
	When emitting OCaml, you often want interface files even if you don't intend to
	hand-write them:

	- A `.mli` makes OCaml's compilation model more explicit and tends to produce
	  clearer module-boundary error messages.
	- It provides a "starting point" if you later want to curate a stable public
	  API for a dune library (hide internals, keep types abstract, etc.).

	What we generate (and what we *don't*)
	--------------------------------------
	This generator intentionally does **not** attempt to derive signatures from
	Haxe types. Doing so correctly would require re-implementing OCaml's type
	inference rules (generalization/value restriction, hidden equalities, etc.) and
	would be easy to drift from the true emitted semantics.

	Instead we run the OCaml compiler's interface printer:

	- Build the emitted project with dune (so `*.cmi` exist in `_build/`).
	- Run `ocamlc -i` (via `ocamlfind`) on each selected `*.ml`.
	- Write the inferred interface to a sibling `*.mli` (skipping files that
	  already have a `*.mli`).

	How selection works
	-------------------
	We currently generate interfaces for `*.ml` under the output directory,
	excluding:

	- `_build/` artifacts
	- `runtime/` (this repo's runtime is already maintained manually and can
	  contain hand-authored `*.mli` files)

	If/when we ship a curated public-API mode, selection will likely become more
	explicit (e.g. only for certain modules, or emitting into a separate folder).
**/
class OcamlMliGenerator {
	static inline final BUILD_DIR = "_build";
	static inline final RUNTIME_DIR = "runtime";

	static function normalizeCompiledBaseName(base:String):String {
		if (base == null || base.length == 0) return base;
		final c = base.charCodeAt(0);
		final isUpper = c >= 65 && c <= 90;
		return isUpper ? (String.fromCharCode(c + 32) + base.substr(1)) : base;
	}

	static function isHiddenOrBuildArtifact(pathRel:String):Bool {
		if (pathRel == null || pathRel.length == 0) return true;
		final parts = pathRel.split("/");
		return parts.indexOf(BUILD_DIR) != -1;
	}

	static function isRuntimePath(pathRel:String):Bool {
		final parts = pathRel.split("/");
		return parts.length > 0 && parts[0] == RUNTIME_DIR;
	}

	static function listMlFilesRecursive(root:String, currentRel:String, out:Array<String>):Void {
		final currentAbs = currentRel.length == 0 ? root : Path.join([root, currentRel]);
		if (!sys.FileSystem.exists(currentAbs) || !sys.FileSystem.isDirectory(currentAbs)) return;

		for (name in sys.FileSystem.readDirectory(currentAbs)) {
			if (name == "." || name == "..") continue;
			final nextRel = currentRel.length == 0 ? name : (currentRel + "/" + name);
			if (isHiddenOrBuildArtifact(nextRel) || isRuntimePath(nextRel)) continue;
			final nextAbs = Path.join([root, nextRel]);
			if (!sys.FileSystem.exists(nextAbs)) continue;
			if (sys.FileSystem.isDirectory(nextAbs)) {
				listMlFilesRecursive(root, nextRel, out);
				continue;
			}
			if (StringTools.endsWith(name, ".ml")) out.push(nextRel);
		}
	}

	static function uniqueDirsContainingCmi(buildRoot:String):Array<String> {
		final dirs = new Map<String, Bool>();

		function walk(abs:String):Void {
			if (!sys.FileSystem.exists(abs) || !sys.FileSystem.isDirectory(abs)) return;
			var hasCmi = false;
			for (name in sys.FileSystem.readDirectory(abs)) {
				if (name == "." || name == "..") continue;
				final child = Path.join([abs, name]);
				if (!sys.FileSystem.exists(child)) continue;
				if (sys.FileSystem.isDirectory(child)) {
					walk(child);
				} else if (StringTools.endsWith(name, ".cmi")) {
					hasCmi = true;
				}
			}
			if (hasCmi) dirs.set(abs, true);
		}

		walk(buildRoot);

		final out:Array<String> = [];
		for (d in dirs.keys()) out.push(d);
		out.sort(Reflect.compare);
		return out;
	}

	static function compiledCmiBaseNames(buildRoot:String):Map<String, Bool> {
		final bases = new Map<String, Bool>();

		function walk(abs:String):Void {
			if (!sys.FileSystem.exists(abs) || !sys.FileSystem.isDirectory(abs)) return;
			for (name in sys.FileSystem.readDirectory(abs)) {
				if (name == "." || name == "..") continue;
				final child = Path.join([abs, name]);
				if (!sys.FileSystem.exists(child)) continue;
				if (sys.FileSystem.isDirectory(child)) {
					walk(child);
					continue;
				}
				if (!StringTools.endsWith(name, ".cmi")) continue;
				final base = Path.withoutExtension(name);
				bases.set(normalizeCompiledBaseName(base), true);
			}
		}

		walk(buildRoot);
		return bases;
	}

	static function tryReadDuneLibraries(outDir:String):Array<String> {
		final dunePath = Path.join([outDir, "dune"]);
		if (!sys.FileSystem.exists(dunePath)) return [];
		final content = sys.io.File.getContent(dunePath);

		// Minimal parse: look for `(libraries a b c)` in the generated dune stanza.
		// This is intentionally conservative: it only needs to cover our emitted
		// scaffold, not arbitrary dune syntax.
		final libs:Array<String> = [];
		final re = ~/\\(libraries\\s+([^\\)]+)\\)/g;
		if (re.match(content)) {
			final raw = re.matched(1);
			for (t in raw.split(" ")) {
				final s = StringTools.trim(t);
				if (s.length == 0) continue;
				// dune can include the local runtime library; ocamlfind won't know it.
				if (s == "hx_runtime") continue;
				libs.push(s);
			}
		}
		return libs;
	}

	static function runCapture(cmd:String, args:Array<String>):{ code:Int, out:String, err:String } {
		final p = new sys.io.Process(cmd, args);
		try {
			final stdout = p.stdout.readAll().toString();
			final stderr = p.stderr.readAll().toString();
			final code = p.exitCode();
			p.close();
			return { code: code, out: stdout, err: stderr };
		} catch (e:Dynamic) {
			try p.close() catch (_:Dynamic) {}
			return { code: 1, out: "", err: "Process failed: " + Std.string(e) };
		}
	}

	/**
		Attempts to infer `*.mli` files using build artifacts found in `_build/`.

		Assumptions / preconditions:
		- The caller already ran `dune build` in `outDir` so that `_build/default`
		  exists and contains `*.cmi` files.
	**/
	public static function tryInferFromBuild(outDir:String):BuildResult {
		final buildDefault = Path.join([outDir, BUILD_DIR, "default"]);
		if (!sys.FileSystem.exists(buildDefault) || !sys.FileSystem.isDirectory(buildDefault)) {
			return Err("ocaml_mli=infer requested but no dune build artifacts found at " + buildDefault);
		}

		// Dune only compiles the dependency closure needed for the requested target.
		// To keep inference robust (and to avoid requiring a "compile everything" pass),
		// we infer `.mli` only for modules that were actually compiled (i.e. have a `.cmi`).
		final compiledBases = compiledCmiBaseNames(buildDefault);

		final mlFiles:Array<String> = [];
		listMlFilesRecursive(outDir, "", mlFiles);
		if (mlFiles.length == 0) return Ok(null);

		final includeDirs = uniqueDirsContainingCmi(buildDefault);
		final dunePkgs = tryReadDuneLibraries(outDir);

		for (rel in mlFiles) {
			final base = normalizeCompiledBaseName(Path.withoutExtension(Path.withoutDirectory(rel)));
			if (!compiledBases.exists(base)) continue;

			final abs = Path.join([outDir, rel]);
			final mliRel = rel.substr(0, rel.length - 3) + ".mli";
			final mliAbs = Path.join([outDir, mliRel]);
			if (sys.FileSystem.exists(mliAbs)) continue;

			final args:Array<String> = [];
			if (dunePkgs.length > 0) {
				args.push("-package");
				args.push(dunePkgs.join(","));
			}
			for (d in includeDirs) {
				args.push("-I");
				args.push(d);
			}
			// Also include source dirs so `#use`-style or local path lookups keep working
			// in early scaffolding (best-effort).
			args.push("-I");
			args.push(outDir);
			args.push("-I");
			args.push(Path.join([outDir, RUNTIME_DIR]));

			args.push("-i");
			args.push(abs);

			final res = runCapture("ocamlfind", ["ocamlc"].concat(args));
			if (res.code != 0) {
				return Err("Failed to infer .mli for " + rel + " (exit " + res.code + "):\n" + (res.err.length > 0 ? res.err : res.out));
			}

			final header = [
				"(* Generated by reflaxe.ocaml: inferred via `ocamlc -i` *)",
				"(* Source: " + rel + " *)",
				""
			].join("\n");
			sys.io.File.saveContent(mliAbs, header + res.out);
		}

		return Ok(null);
	}
}

#end
