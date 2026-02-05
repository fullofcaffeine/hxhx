import haxe.io.Path;

/**
	Stage 2 module resolver skeleton (classpath + transitive import closure).

	Why:
	- A real compiler never sees a single file: it sees a module graph rooted at `-main`.
	- For Haxe-in-Haxe bootstrapping, we need a deterministic, minimal resolver early so
	  typing work has a stable input boundary.
	- This mirrors the same “module closure” idea we validate in `packages/hxhx` Stage 1,
	  but lives *inside* the compiler pipeline we’re incrementally porting to Haxe.

	What:
	- Resolves a `mainModule` (e.g. `demo.A`) to a `.hx` file by searching a list of
	  classpaths (`-cp` roots).
	- Parses the root module and recursively parses its reachable, explicit imports.
	- Ignores wildcard imports (`import a.b.*`) for now (they’re not resolvable without
	  a directory scan + symbol table).
	- Treats missing non-wildcard imports as a hard error (fails fast).

	How:
	- Resolution strategy:
	  1. Try `<cp>/<modulePathWithSlashes>.hx`
	  2. If the import looks like a “subtype in module” (`pack.Mod.SubType`), fall back
	     to `<cp>/pack/Mod.hx` when `<cp>/pack/Mod/SubType.hx` does not exist.
	- Parsing uses `ParserStage.parse`, which can route to either the pure-Haxe frontend
	  or the native OCaml frontend hook (see `ParserStage` hxdoc).
**/
class ResolverStage {
	public static function parseProject(classPaths:Array<String>, mainModule:String):Array<ResolvedModule> {
		final out = new Array<ResolvedModule>();
		final visited = new Map<String, Bool>();

		function visit(modulePath:String):Void {
			if (visited.exists(modulePath)) return;
			visited.set(modulePath, true);

			final filePath = resolveModuleFile(classPaths, modulePath);
			if (filePath == null) {
				throw "import_missing " + modulePath;
			}

			final source = try sys.io.File.getContent(filePath) catch (_:Dynamic) null;
			if (source == null) {
				throw "import_unreadable " + filePath;
			}

			final parsed = try ParserStage.parse(source) catch (e:Dynamic) {
				throw "parse_failed " + filePath + ": " + Std.string(e);
			}
			out.push(new ResolvedModule(modulePath, filePath, parsed));

			final decl = parsed.getDecl();
			for (rawImport in HxModuleDecl.getImports(decl)) {
				final imp = normalizeImport(rawImport);
				if (imp == null) continue;
				if (StringTools.endsWith(imp, ".*")) {
					// Bootstrap rule: treat `import X.*` as a dependency on module `X` rather than
					// performing a directory scan. This supports upstream patterns like `unit.Test.*`.
					final base = imp.substr(0, imp.length - 2);
					// If the base module doesn't exist as a file, treat this as a package-wildcard
					// import (`import pack.*`) and ignore it for graph traversal.
					if (resolveModuleFile(classPaths, base) != null) visit(base);
					continue;
				}
				visit(imp);
			}
		}

		visit(mainModule);
		return out;
	}

	static function normalizeImport(raw:String):Null<String> {
		if (raw == null) return null;
		var s = StringTools.trim(raw);
		if (s.length == 0) return null;

		// Native parser may provide "using Foo" (future-proofing).
		if (StringTools.startsWith(s, "using ")) {
			s = StringTools.trim(s.substr("using ".length));
		}

		// Parser may provide "Foo as Bar"; alias is ignored for resolution.
		final asIdx = s.indexOf(" as ");
		if (asIdx >= 0) s = StringTools.trim(s.substr(0, asIdx));

		return s.length == 0 ? null : s;
	}

	static function resolveModuleFile(classPaths:Array<String>, modulePath:String):Null<String> {
		final parts = modulePath.split(".");
		if (parts.length == 0) return null;

		final direct = parts.join("/") + ".hx";
		for (cp in classPaths) {
			final candidate = Path.join([cp, direct]);
			if (sys.FileSystem.exists(candidate)) return candidate;
		}

		// Heuristic: allow import of a type defined in its module file:
		//   import pack.Mod.SubType
		// and fall back to pack/Mod.hx when pack/Mod/SubType.hx doesn't exist.
		if (parts.length >= 2) {
			final fallbackParts = parts.slice(0, parts.length - 1);
			final fallback = fallbackParts.join("/") + ".hx";
			for (cp in classPaths) {
				final candidate = Path.join([cp, fallback]);
				if (sys.FileSystem.exists(candidate)) return candidate;
			}
		}

		return null;
	}
}
