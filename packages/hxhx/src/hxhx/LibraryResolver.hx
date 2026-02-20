package hxhx;

import haxe.io.Eof;

typedef LibrarySpec = {
	/**
		Directories that should be added to the classpath.
	**/
	final classPaths:Array<String>;

	/**
		`-D` defines provided by the library.
	**/
	final defines:Array<String>;

	/**
		`--macro <expr>` initializers provided by the library.
	**/
	final macros:Array<String>;

	/**
		Other flags we do not model yet.
	**/
	final unknownArgs:Array<String>;
};

/**
	Resolve `-lib/--library` specifications with a `lix`-first strategy.

	Resolution order:
	1) `haxe_libraries/<lib>.hxml` (scoped/lix style, walking parent directories)
	2) `lix run-haxelib path <lib>`
	3) `haxelib path <lib>` (fallback compatibility)
**/
class LibraryResolver {
	static function emptySpec():LibrarySpec {
		return {
			classPaths: [],
			defines: [],
			macros: [],
			unknownArgs: []
		};
	}

	static function haxelibBin():String {
		final v = Sys.getEnv("HAXELIB_BIN");
		return (v == null || v.length == 0) ? "haxelib" : v;
	}

	static function lixBin():String {
		final v = Sys.getEnv("LIX_BIN");
		return (v == null || v.length == 0) ? "lix" : v;
	}

	public static function resolve(lib:String, cwd:String, seen:Map<String, Bool>, depth:Int):LibrarySpec {
		if (depth > 25)
			throw "library resolution depth exceeded while resolving: " + lib;

		if (seen.exists(lib))
			return emptySpec();
		seen.set(lib, true);

		final hxmlPath = findScopedHxml(lib, cwd);
		if (hxmlPath.length > 0)
			return resolveFromHxml(hxmlPath, cwd, seen, depth);

		return resolveViaProcess(lib);
	}

	public static function findScopedHxml(lib:String, cwd:String):String {
		inline function joinPath(base:String, tail:String):String {
			if (base.length == 0)
				return tail;
			if (StringTools.endsWith(base, "/"))
				return base + tail;
			return base + "/" + tail;
		}

		var dir = sys.FileSystem.absolutePath((cwd == null || cwd.length == 0) ? "." : cwd);
		for (_ in 0...10) {
			final candidate = sys.FileSystem.absolutePath(joinPath(dir, "haxe_libraries/" + lib + ".hxml"));
			if (sys.FileSystem.exists(candidate) && !sys.FileSystem.isDirectory(candidate))
				return candidate;
			final parent = sys.FileSystem.absolutePath(joinPath(dir, ".."));
			if (parent == dir)
				break;
			dir = parent;
		}
		return "";
	}

	static function resolveViaProcess(lib:String):LibrarySpec {
		final lixSpec = tryResolveViaCommand(lixBin(), ["run-haxelib", "path", lib]);
		if (lixSpec != null)
			return lixSpec;

		final haxelibSpec = tryResolveViaCommand(haxelibBin(), ["path", lib]);
		if (haxelibSpec != null)
			return haxelibSpec;

		throw "failed to resolve -lib " + lib + " via lix or haxelib";
	}

	static function tryResolveViaCommand(bin:String, args:Array<String>):Null<LibrarySpec> {
		var p:Null<sys.io.Process> = null;
		try {
			p = new sys.io.Process(bin, args);
		} catch (_:String) {
			return null;
		}

		final classPaths = new Array<String>();
		final defines = new Array<String>();
		final macros = new Array<String>();
		final unknownArgs = new Array<String>();

		try {
			while (true) {
				final raw = p.stdout.readLine();
				final line = StringTools.trim(raw);
				if (line.length == 0)
					continue;
				if (!StringTools.startsWith(line, "-")) {
					classPaths.push(line);
					continue;
				}

				if (StringTools.startsWith(line, "-D ")) {
					final def = StringTools.trim(line.substr(3));
					if (def.length > 0)
						defines.push(def);
					continue;
				}
				if (StringTools.startsWith(line, "--macro ")) {
					final expr = StringTools.trim(line.substr(8));
					if (expr.length > 0)
						macros.push(expr);
					continue;
				}
				if (StringTools.startsWith(line, "-cp ")) {
					final cp = StringTools.trim(line.substr(4));
					if (cp.length > 0)
						classPaths.push(cp);
					continue;
				}
				if (StringTools.startsWith(line, "--class-path ")) {
					final cp = StringTools.trim(line.substr(13));
					if (cp.length > 0)
						classPaths.push(cp);
					continue;
				}

				unknownArgs.push(line);
			}
		} catch (_:Eof) {}

		final code = p.exitCode();
		if (code != 0)
			return null;

		return {
			classPaths: classPaths,
			defines: defines,
			macros: macros,
			unknownArgs: unknownArgs
		};
	}

	static function resolveFromHxml(hxmlPath:String, cwd:String, seen:Map<String, Bool>, depth:Int):LibrarySpec {
		final args = Hxml.parseFile(hxmlPath);
		if (args == null)
			throw "failed to parse library hxml: " + hxmlPath;

		final classPaths = new Array<String>();
		final defines = new Array<String>();
		final macros = new Array<String>();
		final unknownArgs = new Array<String>();

		inline function pushUnique(a:Array<String>, v:String):Void {
			if (v == null || v.length == 0)
				return;
			if (a.indexOf(v) == -1)
				a.push(v);
		}

		var i = 0;
		while (i < args.length) {
			final a = args[i];
			switch (a) {
				case "-cp" | "-p" | "--class-path":
					if (i + 1 < args.length)
						pushUnique(classPaths, args[i + 1]);
					i += 2;
				case "-D":
					if (i + 1 < args.length)
						pushUnique(defines, args[i + 1]);
					i += 2;
				case "--macro":
					if (i + 1 < args.length)
						pushUnique(macros, args[i + 1]);
					i += 2;
				case "-lib" | "--library":
					if (i + 1 >= args.length)
						throw "malformed library hxml (missing value after " + a + "): " + hxmlPath;
					final dep = args[i + 1];
					final depSpec = resolve(dep, cwd, seen, depth + 1);
					for (cp in depSpec.classPaths)
						pushUnique(classPaths, cp);
					for (d in depSpec.defines)
						pushUnique(defines, d);
					for (m in depSpec.macros)
						pushUnique(macros, m);
					for (u in depSpec.unknownArgs)
						pushUnique(unknownArgs, u);
					i += 2;
				case _:
					if (a != null && a.length > 0 && StringTools.startsWith(a, "-"))
						pushUnique(unknownArgs, a);
					i += 1;
			}
		}

		return {
			classPaths: classPaths,
			defines: defines,
			macros: macros,
			unknownArgs: unknownArgs
		};
	}
}
