package hxhx.macro;

import haxe.crypto.Sha256;
import haxe.io.Path;
import hxhxmacrohost.NativeMacroModuleAbi;
import hxhxmacrohost.NativeMacroModuleActivation;
import hxhxmacrohost.NativeMacroModuleReceipt;
import hxhxmacrohost.NativeMacroModuleReceipt.NativeMacroModuleExpectation;
import hxhxmacrohost.NativeMacroModuleReceipt.NativeMacroModuleFile;
import hxhxmacrohost.NativeMacroModuleReceipt.NativeMacroModuleToolchain;
import hxhx.CompilerJsonValue;
import sys.FileSystem;
import sys.io.File;

/** How to start the hxhx compiler that compiles a plugin: a program and the arguments before the request. */
typedef ProjectMacroPluginCommand = {
	final program:String;
	final leadingArgs:Array<String>;
}

/** Everything that decides one project-macro plugin, in the form the cache key and the build need. */
typedef ProjectMacroPluginRequest = {
	/** `pack.Type.method` keys in registration order; the plugin registers exactly these. */
	final declarations:Array<String>;

	/** Absolute project classpaths; the plugin compilation compiles their modules as macro code. */
	final macroClassPaths:Array<String>;

	/** The requesting compile's complete classpath list, in lookup order (part of the identity). */
	final classPaths:Array<String>;

	/** The request's `-D` values (`name` or `name=value`), forwarded to the plugin compilation. */
	final defines:Array<String>;

	final cwd:String;

	/** The classpath with `hxhxmacrohost.MacroDeclarationPlugin` and `MacroSyntaxWire`. */
	final supportClassPath:String;

	/** Directories whose OCaml sources the emitter copies into every plugin (runtime and shims). */
	final runtimeSourceDirectories:Array<String>;

	final cacheRoot:String;

	/** Digest of the running hxhx executable (`NativeMacroModuleHostIdentity.executableDigest`). */
	final compilerIdentity:String;

	/** OCaml version of the running hxhx executable; the plugin must be built by the same version. */
	final ocamlVersion:String;

	final compiler:ProjectMacroPluginCommand;

	/** Executable names for `dune` and `ocamlopt`, normally looked up on `PATH`. */
	final dune:String;

	final ocamlopt:String;

	/** `native` (`.cmxs`) or `bytecode` (`.cma`): the artifact this compiler process loads. */
	final artifactKind:String;

	/** How long to wait for another process that is building the same plugin. */
	final lockTimeoutSeconds:Float;

	/** Wall-clock limit for each tool run of a build (the child compiler, `dune`); the tool is killed after it. */
	final buildTimeoutSeconds:Float;

	/** Receives one human-readable line before the cache waits for a lock or builds. */
	final progress:String->Void;
}

/** Whether `ensure` reused a valid cached plugin or built one, and why it built. */
enum ProjectMacroPluginOutcome {
	Reused;
	Built(reason:String);
}

typedef ProjectMacroPluginResult = {
	final activation:NativeMacroModuleActivation;
	final outcome:ProjectMacroPluginOutcome;
	final receiptPath:String;
	final cacheKey:String;
}

/**
	Builds, caches, and validates the native plugin that runs a project's expression macros.

	Why
	- hxhx executes a project macro such as `Identity.preserve(...)` by loading an OCaml plugin that
	  contains the project's real macro classes, compiled by hxhx's own Stage3 emitter. Building
	  that plugin takes tens of seconds, so a second compile with the same inputs must reuse it,
	  while any change that could alter the plugin must rebuild it. A plugin built for other
	  inputs must never load.

	What
	- `ensure(request)` returns a validated activation for the request's plugin. It reuses the
	  cached plugin when its receipt validates (`NativeMacroModuleReceipt.validate`), and otherwise
	  builds a new one, writes its receipt, and validates that.
	- Cache layout: `<cacheRoot>/<cacheKey>/receipt.json` plus one `build-<id>/` directory. The
	  cache key is a SHA-256 over every input known before building: the key schema, the compiler
	  identity and OCaml version, the plugin ABI and macro API versions, the declarations, the
	  macro classpaths, the full classpath list, the defines, the working directory, the support
	  classpath, the `OCAMLPARAM` environment value, and the digest of the OCaml runtime and shim
	  sources the plugin is built with.
	- Inputs found only while building are bound by the receipt: every Haxe source file the plugin
	  compilation read is recorded with its SHA-256, so editing a macro class (or anything it
	  uses) invalidates the plugin even though the key is unchanged.
	- Each build gets a fresh plugin id (`hxhx.project-macro.<build id>`), so every plugin library
	  has unique OCaml unit names and two builds can never collide inside one process.

	How (one build)
	1. Take the per-key lock (a directory renamed into place, so only one process wins).
	2. Check the toolchain: `ocamlopt -version` must equal the compiler's OCaml version, and `dune`
	   must exist. A missing or mismatched tool fails with one diagnostic, before anything is built.
	3. Run hxhx as a child process with `--hxhx-macro-classpath` for each project classpath,
	   `-main hxhxmacrohost.MacroDeclarationPlugin`, and the plugin defines. The child prints the
	   library it generated and the source files it read (`macro_context_source[i]=`).
	4. Run `dune build` for the library's `.cma` and `.cmxs`.
	5. Write the receipt atomically (temporary file, then rename), delete older builds of the
	   same key, release the lock, and validate the receipt like any cached one.

	Gotchas
	- Adding a new file that changes which file an import or type lookup selects, without editing
	  any file the plugin read, is not detected (`haxe_ocaml-9sj5p.4` docs list this limit).
	- Each tool run has a wall-clock limit (`buildTimeoutSeconds`); output is merged and kept for
	  the failure message.
	- A source whose modification time is later than the start of the build is refused, so an edit
	  made while the child compiler ran cannot be recorded with a digest of text it never compiled.
	- A reused plugin is not compared with the current `ocamlopt -config`. The plugin must match
	  the hxhx binary, which the key binds by executable digest and OCaml version; the `PATH`
	  toolchain matters only while building, where its version is checked.
	- A rebuild keeps the build the previous receipt named (a concurrent compile may have validated
	  that receipt and be loading its plugin); every other build directory, including partial ones
	  left by interrupted builds, is deleted.
**/
class ProjectMacroPluginCache {
	public static inline final KEY_SCHEMA:String = "hxhx.project-macro-plugin.v1";
	public static inline final RECEIPT_NAME:String = "receipt.json";
	static inline final LOCK_NAME:String = ".lock";
	static inline final STALE_LOCK_SECONDS:Float = 1800.0;

	/** Default cache root: `$XDG_CACHE_HOME/hxhx/macro-plugins`, `~/.cache/hxhx/macro-plugins`, or `%LOCALAPPDATA%`. */
	public static function defaultRoot():Null<String> {
		for (candidate in [
			{env: "XDG_CACHE_HOME", tail: ["hxhx", "macro-plugins"]},
			{env: "HOME", tail: [".cache", "hxhx", "macro-plugins"]},
			{env: "LOCALAPPDATA", tail: ["hxhx", "macro-plugins"]}
		]) {
			final base = Sys.getEnv(candidate.env);
			if (base != null && StringTools.trim(base).length > 0)
				return Path.join([StringTools.trim(base)].concat(candidate.tail));
		}
		return null;
	}

	/** Digest of the OCaml sources (`.ml`, `.mli`) in `directories`, by file name and content. */
	public static function runtimeDigest(directories:Array<String>):String {
		final parts = new Array<Null<String>>();
		for (directory in directories) {
			if (!FileSystem.exists(directory) || !FileSystem.isDirectory(directory))
				throw "project macro plugin: runtime source directory not found: " + directory;
			final names = [
				for (name in FileSystem.readDirectory(directory))
					if (StringTools.endsWith(name, ".ml") || StringTools.endsWith(name, ".mli")) name
			];
			names.sort(compareStrings);
			parts.push(Path.withoutDirectory(directory));
			for (name in names) {
				parts.push(name);
				parts.push(File.getContent(Path.join([directory, name])));
			}
		}
		return Sha256.encode(CompilerCacheIdentity.encode(parts));
	}

	/** The cache key for `request`, given the digest of its runtime sources. */
	public static function cacheKey(request:ProjectMacroPluginRequest, runtimeSourceDigest:String):String {
		function list(values:Array<String>):String
			return CompilerCacheIdentity.encode([for (value in values) value]);
		return Sha256.encode(CompilerCacheIdentity.encode([
			KEY_SCHEMA,
			request.compilerIdentity,
			request.ocamlVersion,
			Std.string(NativeMacroModuleAbi.ABI_VERSION),
			Std.string(NativeMacroModuleAbi.MACRO_API_VERSION),
			list(request.declarations),
			list(request.macroClassPaths),
			list(request.classPaths),
			list(sortedCopy(request.defines)),
			request.cwd,
			request.supportClassPath,
			Sys.getEnv("OCAMLPARAM"),
			runtimeSourceDigest
		]));
	}

	/** Reuse or build the request's plugin; throws a user-facing String when no plugin can be provided. */
	public static function ensure(request:ProjectMacroPluginRequest):ProjectMacroPluginResult {
		if (request.declarations.length == 0)
			throw "project macro plugin: no declarations to build";
		final digest = runtimeDigest(request.runtimeSourceDirectories);
		final key = cacheKey(request, digest);
		final keyDirectory = Path.join([request.cacheRoot, key]);
		final receiptPath = Path.join([keyDirectory, RECEIPT_NAME]);
		final expectation:NativeMacroModuleExpectation = {
			cacheKey: key,
			compilerIdentity: request.compilerIdentity,
			ocamlVersion: request.ocamlVersion,
			runtimeDigest: digest,
			declarations: request.declarations
		};
		var reason = "no cached plugin for these inputs";
		if (FileSystem.exists(receiptPath)) {
			try {
				return reused(NativeMacroModuleReceipt.validate(receiptPath, expectation, request.artifactKind), receiptPath, key);
			} catch (error:String) {
				reason = error;
			}
		}

		FileSystem.createDirectory(keyDirectory);
		request.progress("hxhx: building project macro plugin for " + request.declarations.join(", ") + " (" + firstLine(reason) + ")...");
		final lock = acquireLock(keyDirectory, request.lockTimeoutSeconds, request.progress);
		try {
			// Another process may have finished the same build while this one waited for the lock.
			if (FileSystem.exists(receiptPath)) {
				try {
					final result = reused(NativeMacroModuleReceipt.validate(receiptPath, expectation, request.artifactKind), receiptPath, key);
					releaseLock(lock);
					return result;
				} catch (error:String) {}
			}
			build(request, key, digest, keyDirectory, receiptPath);
		} catch (error:String) {
			releaseLock(lock);
			throw error;
		} catch (error:haxe.Exception) {
			releaseLock(lock);
			throw "project macro plugin: " + error.message;
		}
		releaseLock(lock);
		return {
			activation: NativeMacroModuleReceipt.validate(receiptPath, expectation, request.artifactKind),
			outcome: Built(reason),
			receiptPath: receiptPath,
			cacheKey: key
		};
	}

	static function firstLine(text:String):String {
		final newline = text.indexOf("\n");
		return newline < 0 ? text : text.substr(0, newline);
	}

	static function reused(activation:NativeMacroModuleActivation, receiptPath:String, key:String):ProjectMacroPluginResult {
		return {
			activation: activation,
			outcome: Reused,
			receiptPath: receiptPath,
			cacheKey: key
		};
	}

	static function build(request:ProjectMacroPluginRequest, key:String, runtimeSourceDigest:String, keyDirectory:String, receiptPath:String):Void {
		final toolchain = checkToolchain(request);
		// A source edited while the plugin compiles would be hashed after its old text was compiled;
		// such a build is refused instead of recorded (see the mtime check below).
		final buildStarted = Sys.time() * 1000.0;
		final buildId = Sha256.encode(key + ":" + Sys.time() + ":" + Std.random(0x3fffffff)).substr(0, 16);
		final pluginId = "hxhx.project-macro." + buildId;
		final buildName = "build-" + buildId;
		final outDirectory = Path.join([keyDirectory, buildName, "plugin"]);
		FileSystem.createDirectory(outDirectory);
		// Only the lock holder writes temporary receipts; any left now belong to an interrupted build.
		for (entry in FileSystem.readDirectory(keyDirectory))
			if (StringTools.startsWith(entry, RECEIPT_NAME + ".") && StringTools.endsWith(entry, ".tmp"))
				FileSystem.deleteFile(Path.join([keyDirectory, entry]));

		final args = request.compiler.leadingArgs.concat(["--hxhx-no-run", "--hxhx-out", outDirectory, "--cwd", request.cwd]);
		for (classPath in request.macroClassPaths) {
			args.push("--hxhx-macro-classpath");
			args.push(classPath);
		}
		args.push("-cp");
		args.push(request.supportClassPath);
		for (define in request.defines) {
			args.push("-D");
			args.push(define);
		}
		for (arg in [
			"-main",
			backend.ocaml.Stage3OcamlMacroPluginEntry.PLUGIN_ENTRY_TYPE,
			"-D",
			"ocaml_dune_layout=plugin",
			"-D",
			"ocaml_plugin_register_macro=" + pluginId,
			"-D",
			backend.ocaml.Stage3OcamlMacroPluginEntry.DECLARATIONS_DEFINE + "=" + request.declarations.join(",")
		])
			args.push(arg);
		final compile = ProjectMacroPluginProcess.run(request.compiler.program, args, request.buildTimeoutSeconds);
		if (compile.timedOut)
			throw "the project macro plugin compile did not finish within "
				+ request.buildTimeoutSeconds
				+ " s and was stopped (set HXHX_MACRO_PLUGIN_BUILD_TIMEOUT to allow longer)";
		if (compile.code != 0)
			throw "the project macro plugin compile failed (exit "
				+ compile.code
				+ "):\n"
				+ ProjectMacroPluginProcess.tail(compile.output, 40);

		final library = backend.ocaml.Stage3OcamlMacroPluginEntry.libraryName(pluginId);
		var libraryArchive:Null<String> = null;
		final sources = new Array<String>();
		for (line in compile.output.split("\n")) {
			if (StringTools.startsWith(line, "exe="))
				libraryArchive = line.substr("exe=".length);
			else if (StringTools.startsWith(line, "macro_context_source[")) {
				final separator = line.indexOf("]=");
				if (separator > 0)
					sources.push(line.substr(separator + 2));
			}
		}
		if (libraryArchive == null || Path.withoutDirectory(libraryArchive) != library + ".cma")
			throw "the project macro plugin compile did not report its library `"
				+ library
				+ ".cma`:\n"
				+ ProjectMacroPluginProcess.tail(compile.output, 40);
		if (sources.length == 0)
			throw "the project macro plugin compile did not report its macro sources:\n" + ProjectMacroPluginProcess.tail(compile.output, 40);

		final dune = ProjectMacroPluginProcess.run(request.dune, [
			"build",
			"--root",
			outDirectory,
			"--display",
			"quiet",
			"./" + library + ".cma",
			"./" + library + ".cmxs"
		], request.buildTimeoutSeconds);
		if (dune.timedOut)
			throw "dune did not finish building the project macro plugin within "
				+ request.buildTimeoutSeconds
				+ " s and was stopped (set HXHX_MACRO_PLUGIN_BUILD_TIMEOUT to allow longer)";
		if (dune.code != 0)
			throw "dune could not build the project macro plugin (exit "
				+ dune.code
				+ "):\n"
				+ ProjectMacroPluginProcess.tail(dune.output, 40);
		final builtRelative = buildName + "/plugin/_build/default/" + library;
		for (extension in [".cma", ".cmxs"])
			if (!FileSystem.exists(Path.join([keyDirectory, builtRelative + extension])))
				throw "dune finished without building " + builtRelative + extension;

		final recordedSources = new Array<NativeMacroModuleFile>();
		for (source in sources) {
			if (CompilerBundledSources.owns(source))
				continue;
			if (FileSystem.stat(source).mtime.getTime() > buildStarted)
				throw "macro source " + source + " changed while its plugin was being built; compile again";
			recordedSources.push({path: source, sha256: NativeMacroModuleReceipt.fileSha256(source)});
		}
		final receipt = NativeMacroModuleReceipt.encode({
			cacheKey: key,
			compilerIdentity: request.compilerIdentity,
			pluginId: pluginId,
			declarations: request.declarations,
			toolchain: toolchain,
			runtimeDigest: runtimeSourceDigest,
			sources: recordedSources,
			native: {
				path: builtRelative + ".cmxs",
				sha256: NativeMacroModuleReceipt.fileSha256(Path.join([keyDirectory, builtRelative + ".cmxs"]))
			},
			bytecode: {path: builtRelative + ".cma", sha256: NativeMacroModuleReceipt.fileSha256(Path.join([keyDirectory, builtRelative + ".cma"]))}
		});
		// A concurrent compile may have validated the previous receipt and be about to load its
		// plugin, so the build that receipt names stays; every other build (older generations and
		// partial directories of interrupted builds) is removed.
		final previousBuild = receiptBuildName(receiptPath);
		final temporary = receiptPath + "." + buildId + ".tmp";
		File.saveContent(temporary, receipt);
		FileSystem.rename(temporary, receiptPath);
		for (entry in FileSystem.readDirectory(keyDirectory))
			if (StringTools.startsWith(entry, "build-") && entry != buildName && entry != previousBuild)
				deleteTree(Path.join([keyDirectory, entry]));
	}

	/** Fails before building when `dune` or `ocamlopt` is missing or `ocamlopt` is another OCaml version. */
	static function checkToolchain(request:ProjectMacroPluginRequest):NativeMacroModuleToolchain {
		final missing = "project macros need `dune` and the OCaml native compiler (`ocamlopt`) on PATH to build their native plugin";
		final ocamlVersion = ProjectMacroPluginProcess.run(request.ocamlopt, ["-version"]);
		if (ocamlVersion.code != 0)
			throw missing + "; `" + request.ocamlopt + " -version` failed: " + ProjectMacroPluginProcess.tail(ocamlVersion.output, 3);
		final version = StringTools.trim(ocamlVersion.output);
		if (version != request.ocamlVersion)
			throw "project macro plugins must be built by the OCaml version that built this hxhx ("
				+ request.ocamlVersion
				+ "), but `"
				+ request.ocamlopt
				+ "` on PATH is OCaml "
				+ version;
		final duneVersion = ProjectMacroPluginProcess.run(request.dune, ["--version"]);
		if (duneVersion.code != 0)
			throw missing + "; `" + request.dune + " --version` failed: " + ProjectMacroPluginProcess.tail(duneVersion.output, 3);
		final config = ProjectMacroPluginProcess.run(request.ocamlopt, ["-config"]);
		if (config.code != 0)
			throw missing + "; `" + request.ocamlopt + " -config` failed: " + ProjectMacroPluginProcess.tail(config.output, 3);
		return {
			ocaml: version,
			dune: StringTools.trim(duneVersion.output),
			ocamlConfigSha256: Sha256.encode(config.output)
		};
	}

	/**
		Take the per-key build lock and return its path.

		The lock is a directory that holds an `owner` file with the owner's process id. A process
		creates its own uniquely named directory and renames it to `.lock`; renaming onto an existing
		non-empty directory fails, so exactly one process holds the lock. A lock is stale when its
		owner process no longer exists (an interrupted build, for example Ctrl-C) or when it is older
		than 30 minutes. A stale lock is first renamed away to a unique name, so only one waiter can
		remove it, and then deleted.
	**/
	static function acquireLock(keyDirectory:String, timeoutSeconds:Float, progress:String->Void):String {
		final lockPath = Path.join([keyDirectory, LOCK_NAME]);
		final deadline = Sys.time() + timeoutSeconds;
		final ownPid = hxhxmacrohost.NativeMacroModuleHostIdentity.processId();
		var announced = false;
		while (true) {
			final candidate = Path.join([keyDirectory, ".lock-" + uniqueSuffix()]);
			FileSystem.createDirectory(candidate);
			File.saveContent(Path.join([candidate, "owner"]), Std.string(ownPid) + "\n");
			final acquired = try {
				FileSystem.rename(candidate, lockPath);
				true;
			} catch (_:String) {
				false;
			} catch (_:haxe.Exception) {
				false;
			}
			if (acquired)
				return lockPath;
			deleteTree(candidate);
			if (isStaleLock(lockPath)) {
				final staleName = Path.join([keyDirectory, ".lock-stale-" + uniqueSuffix()]);
				final claimed = try {
					FileSystem.rename(lockPath, staleName);
					true;
				} catch (_:String) {
					false;
				} catch (_:haxe.Exception) {
					false;
				}
				if (claimed)
					deleteTree(staleName);
				continue;
			}
			if (!announced) {
				progress("hxhx: waiting for another hxhx process that is building this project macro plugin (lock: " + lockPath + ")");
				announced = true;
			}
			if (Sys.time() > deadline)
				throw "timed out after "
					+ timeoutSeconds
					+ " s waiting for another hxhx process to finish building this project macro plugin (lock: "
					+ lockPath
					+ ")";
			Sys.sleep(0.2);
		}
	}

	/** A lock whose owner process is gone, whose owner file is unreadable, or that is older than 30 minutes. */
	static function isStaleLock(lockPath:String):Bool {
		final owner = Path.join([lockPath, "owner"]);
		if (!FileSystem.exists(owner))
			return FileSystem.exists(lockPath) && ageSeconds(lockPath) > 5.0;
		if (ageSeconds(owner) > STALE_LOCK_SECONDS)
			return true;
		final pid = Std.parseInt(StringTools.trim(File.getContent(owner)));
		return pid == null || !ProjectMacroPluginProcess.isAlive(pid);
	}

	static function ageSeconds(path:String):Float {
		return (Sys.time() * 1000.0 - FileSystem.stat(path).mtime.getTime()) / 1000.0;
	}

	static function uniqueSuffix():String {
		return Sha256.encode(Sys.time() + ":" + Std.random(0x3fffffff)).substr(0, 12);
	}

	static function releaseLock(lockPath:String):Void {
		if (FileSystem.exists(lockPath))
			deleteTree(lockPath);
	}

	static function deleteTree(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (!FileSystem.isDirectory(path)) {
			FileSystem.deleteFile(path);
			return;
		}
		for (entry in FileSystem.readDirectory(path))
			deleteTree(Path.join([path, entry]));
		FileSystem.deleteDirectory(path);
	}

	/** The `build-<id>` directory the receipt at `receiptPath` names, or `null` when it names none. */
	static function receiptBuildName(receiptPath:String):Null<String> {
		if (!FileSystem.exists(receiptPath))
			return null;
		try {
			switch (hxhx.CompilerJsonParser.parse(File.getContent(receiptPath))) {
				case JsonObject(fields):
					switch (fields.get("artifacts")) {
						case JsonObject(artifacts):
							switch (artifacts.get("native")) {
								case JsonObject(native):
									switch (native.get("path")) {
										case JsonString(path):
											final slash = path.indexOf("/");
											return slash > 0 ? path.substr(0, slash) : null;
										case _:
									}
								case _:
							}
						case _:
					}
				case _:
			}
		} catch (_:String) {} catch (_:haxe.Exception) {}
		return null;
	}

	static function sortedCopy(values:Array<String>):Array<String> {
		final out = values.copy();
		out.sort(compareStrings);
		return out;
	}

	static function compareStrings(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
