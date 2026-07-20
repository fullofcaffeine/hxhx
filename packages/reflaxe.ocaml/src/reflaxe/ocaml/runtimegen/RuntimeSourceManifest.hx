package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceFile;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceModule;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
	Loads and verifies the repository-owned OCaml compatibility runtime.

	The checked JSON file is the dependency authority. Source scanning may be used
	by a separate audit test, but compilation never invents dependencies from OCaml
	text. A missing, added, or modified runtime source therefore fails before any
	file is copied into generated output.
**/
class RuntimeSourceManifest {
	public static inline final FILE_NAME = "runtime-manifest.json";
	public static inline final MODEL = "reflaxe-ocaml-runtime-sources";
	public static inline final SCHEMA_VERSION = 1;
	public static inline final APPLICATION_SCOPE = "application";
	public static inline final TOOLING_SCOPE = "tooling";

	/** Loads the runtime catalog and verifies every declared source byte. **/
	public static function load(runtimeDirectory:String):RuntimeSourceManifestSnapshot {
		final root = Path.normalize(FileSystem.absolutePath(runtimeDirectory));
		if (!FileSystem.exists(root) || !FileSystem.isDirectory(root))
			throw 'OCaml runtime source directory "$runtimeDirectory" is missing.';
		final manifestPath = Path.join([root, FILE_NAME]);
		if (!FileSystem.exists(manifestPath) || FileSystem.isDirectory(manifestPath))
			throw 'OCaml runtime source manifest "$manifestPath" is missing.';
		final value:Dynamic = try {
			Json.parse(File.getContent(manifestPath));
		} catch (error:Dynamic) {
			throw 'OCaml runtime source manifest is invalid JSON: ${Std.string(error)}';
		}
		assertFields(value, ["entries", "model", "runtimeVersion", "schemaVersion"], "source manifest");
		if (requiredInt(value, "schemaVersion") != SCHEMA_VERSION || requiredString(value, "model") != MODEL)
			throw "OCaml runtime source manifest uses an unsupported schema or model.";
		final runtimeVersion = requiredToken(value, "runtimeVersion");
		final modules = parseModules(requiredArray(value, "entries"), root);
		validateDependencies(modules);
		validateSourceCoverage(root, modules);
		final snapshot:RuntimeSourceManifestSnapshot = {
			schemaVersion: SCHEMA_VERSION,
			model: MODEL,
			runtimeVersion: runtimeVersion,
			revision: calculateRevision(runtimeVersion, modules),
			modules: modules
		};
		validateDependencyEligibility(snapshot);
		return snapshot;
	}

	/** Resolves an exact, profile-checked transitive module closure. **/
	public static function resolveClosure(snapshot:RuntimeSourceManifestSnapshot, roots:Array<String>, profile:String,
			allowTooling:Bool):Array<RuntimeSourceModule> {
		final normalizedProfile = validatedProfile(profile);
		final byName:Map<String, RuntimeSourceModule> = [for (entry in snapshot.modules) entry.module => entry];
		final selected:Map<String, Bool> = [];
		final visiting:Map<String, Bool> = [];

		function visit(moduleName:String, requestedBy:String):Void {
			final entry = byName.get(moduleName);
			if (entry == null)
				throw 'Unknown OCaml runtime module "$moduleName" requested by $requestedBy.';
			if (entry.scope == TOOLING_SCOPE && !allowTooling)
				throw 'OCaml runtime module "$moduleName" is tooling-only and cannot enter an application runtime.';
			if (!entry.profiles.contains(normalizedProfile))
				throw 'OCaml runtime module "$moduleName" is not allowed in the "$normalizedProfile" profile.';
			if (selected.exists(moduleName))
				return;
			if (visiting.exists(moduleName))
				throw 'OCaml runtime dependency cycle reaches "$moduleName".';
			visiting.set(moduleName, true);
			for (dependency in entry.dependencies)
				visit(dependency, 'runtime module "$moduleName"');
			visiting.remove(moduleName);
			selected.set(moduleName, true);
		}

		final normalizedRoots = normalizedTokens(roots, "runtime roots");
		for (root in normalizedRoots)
			visit(root, "the compiler runtime plan");
		return snapshot.modules.filter(entry -> selected.exists(entry.module));
	}

	/** Returns all modules legal for an explicit full-runtime build. **/
	public static function fullRoots(snapshot:RuntimeSourceManifestSnapshot, profile:String, allowTooling:Bool):Array<String> {
		final normalizedProfile = validatedProfile(profile);
		return [
			for (entry in snapshot.modules)
				if (entry.profiles.contains(normalizedProfile) && (allowTooling || entry.scope != TOOLING_SCOPE)) entry.module
		];
	}

	static function parseModules(rawEntries:Array<Dynamic>, root:String):Array<RuntimeSourceModule> {
		final modules = new Array<RuntimeSourceModule>();
		final seenModules:Map<String, Bool> = [];
		final seenFiles:Map<String, Bool> = [];
		var previousModule:Null<String> = null;
		for (raw in rawEntries) {
			assertFields(raw, [
				"dependencies",
				"duneLibraries",
				"files",
				"license",
				"module",
				"profiles",
				"scope"
			], "runtime module entry");
			final moduleName = requiredToken(raw, "module");
			if (!~/^[A-Za-z][A-Za-z0-9_]*$/.match(moduleName))
				throw 'OCaml runtime module "$moduleName" is not a valid module token.';
			if (seenModules.exists(moduleName))
				throw 'OCaml runtime source manifest repeats module "$moduleName".';
			if (previousModule != null && compareStrings(previousModule, moduleName) >= 0)
				throw 'OCaml runtime source modules are not in deterministic order at "$moduleName".';
			seenModules.set(moduleName, true);
			previousModule = moduleName;
			final scope = requiredToken(raw, "scope");
			if (scope != APPLICATION_SCOPE && scope != TOOLING_SCOPE)
				throw 'OCaml runtime module "$moduleName" has unsupported scope "$scope".';
			final profiles = normalizedTokens(requiredStringArray(raw, "profiles"), 'profiles for "$moduleName"');
			for (profile in profiles)
				validatedProfile(profile);
			final files = parseFiles(requiredArray(raw, "files"), root, moduleName, seenFiles);
			final license = requiredToken(raw, "license");
			if (license != "MIT")
				throw 'OCaml runtime module "$moduleName" has unsupported license "$license".';
			modules.push({
				module: moduleName,
				scope: scope,
				files: files,
				dependencies: normalizedTokens(requiredStringArray(raw, "dependencies"), 'dependencies for "$moduleName"'),
				duneLibraries: normalizedTokens(requiredStringArray(raw, "duneLibraries"), 'Dune libraries for "$moduleName"'),
				profiles: profiles,
				license: license
			});
		}
		if (modules.length == 0)
			throw "OCaml runtime source manifest contains no modules.";
		return modules;
	}

	static function parseFiles(rawFiles:Array<Dynamic>, root:String, moduleName:String, seen:Map<String, Bool>):Array<RuntimeSourceFile> {
		if (rawFiles.length == 0)
			throw 'OCaml runtime module "$moduleName" contains no source files.';
		final files = new Array<RuntimeSourceFile>();
		var previousPath:Null<String> = null;
		for (raw in rawFiles) {
			assertFields(raw, ["path", "sha256"], 'source file for "$moduleName"');
			final path = normalizeFileName(requiredString(raw, "path"));
			if (moduleNameFromFile(path) != moduleName)
				throw 'OCaml runtime source "$path" does not define the declared module "$moduleName".';
			if (seen.exists(path))
				throw 'OCaml runtime source "$path" belongs to more than one module.';
			if (previousPath != null && compareStrings(previousPath, path) >= 0)
				throw 'OCaml runtime files for "$moduleName" are not in deterministic order at "$path".';
			seen.set(path, true);
			previousPath = path;
			final expected = normalizedSha256(requiredString(raw, "sha256"), path);
			final absolute = Path.join([root, path]);
			if (!FileSystem.exists(absolute) || FileSystem.isDirectory(absolute))
				throw 'OCaml runtime source "$path" is missing.';
			final bytes = File.getBytes(absolute);
			final actual = Sha256.make(bytes).toHex();
			if (actual != expected)
				throw 'OCaml runtime source "$path" changed: expected $expected, found $actual.';
			files.push({path: path, sha256: "sha256:" + actual, bytes: bytes.length});
		}
		return files;
	}

	static function moduleNameFromFile(path:String):String {
		return path.endsWith(".mli") ? path.substr(0, path.length - 4) : path.substr(0, path.length - 3);
	}

	static function validateDependencies(modules:Array<RuntimeSourceModule>):Void {
		final known:Map<String, Bool> = [for (entry in modules) entry.module => true];
		for (entry in modules)
			for (dependency in entry.dependencies)
				if (!known.exists(dependency))
					throw 'OCaml runtime module "${entry.module}" names unknown dependency "$dependency".';
	}

	static function validateDependencyEligibility(snapshot:RuntimeSourceManifestSnapshot):Void {
		for (entry in snapshot.modules)
			for (profile in entry.profiles)
				resolveClosure(snapshot, [entry.module], profile, entry.scope == TOOLING_SCOPE);
	}

	static function validateSourceCoverage(root:String, modules:Array<RuntimeSourceModule>):Void {
		final declared:Map<String, Bool> = [];
		for (entry in modules)
			for (file in entry.files)
				declared.set(file.path, true);
		final names = FileSystem.readDirectory(root);
		names.sort(compareStrings);
		for (name in names) {
			if (!name.endsWith(".ml") && !name.endsWith(".mli"))
				continue;
			if (!declared.exists(name))
				throw 'OCaml runtime source "$name" is not declared by $FILE_NAME.';
		}
	}

	static function calculateRevision(runtimeVersion:String, modules:Array<RuntimeSourceModule>):String {
		final canonical:Array<Dynamic> = [
			MODEL,
			SCHEMA_VERSION,
			runtimeVersion,
			[
				for (entry in modules) [
					entry.module,
					entry.scope,
					[for (file in entry.files) [file.path, file.sha256, file.bytes]],
					entry.dependencies,
					entry.duneLibraries,
					entry.profiles,
					entry.license
				]
			]
		];
		return "sha256:" + Sha256.encode(Json.stringify(canonical));
	}

	static function normalizeFileName(value:String):String {
		final path = value == null ? "" : value.replace("\\", "/");
		if (path.length == 0
			|| Path.isAbsolute(path)
			|| path.contains("/")
			|| path == "."
			|| path == ".."
			|| (!path.endsWith(".ml") && !path.endsWith(".mli")))
			throw 'OCaml runtime source path "$value" must be one top-level .ml or .mli file.';
		return path;
	}

	static function normalizedSha256(value:String, path:String):String {
		final normalized = value == null ? "" : value.trim().toLowerCase();
		if (!~/^[0-9a-f]{64}$/.match(normalized))
			throw 'OCaml runtime source "$path" has an invalid SHA-256 digest.';
		return normalized;
	}

	static function normalizedTokens(values:Array<String>, label:String):Array<String> {
		final out = new Array<String>();
		final seen:Map<String, Bool> = [];
		for (raw in values) {
			final value = raw == null ? "" : raw.trim();
			if (value.length == 0)
				throw 'OCaml runtime $label contains an empty value.';
			if (seen.exists(value))
				throw 'OCaml runtime $label repeats "$value".';
			seen.set(value, true);
			out.push(value);
		}
		out.sort(compareStrings);
		return out;
	}

	static function validatedProfile(value:String):String {
		final profile = value == null ? "" : value.trim().toLowerCase();
		if (profile != "portable" && profile != "metal")
			throw 'OCaml runtime profile "$value" must be portable or metal.';
		return profile;
	}

	static function assertFields(value:Dynamic, allowed:Array<String>, label:String):Void {
		final expected = allowed.copy();
		expected.sort(compareStrings);
		final actual = Reflect.fields(value);
		actual.sort(compareStrings);
		if (Json.stringify(actual) != Json.stringify(expected))
			throw 'OCaml runtime $label fields do not match the schema.';
	}

	static function requiredArray(value:Dynamic, field:String):Array<Dynamic> {
		final raw:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(raw, Array))
			throw 'OCaml runtime source manifest field "$field" must be an array.';
		return cast raw;
	}

	static function requiredStringArray(value:Dynamic, field:String):Array<String> {
		final raw = requiredArray(value, field);
		final out = new Array<String>();
		for (item in raw) {
			if (!Std.isOfType(item, String))
				throw 'OCaml runtime source manifest field "$field" must contain only strings.';
			out.push(cast item);
		}
		return out;
	}

	static function requiredString(value:Dynamic, field:String):String {
		final raw:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(raw, String))
			throw 'OCaml runtime source manifest field "$field" must be a string.';
		return cast raw;
	}

	static function requiredToken(value:Dynamic, field:String):String {
		final token = requiredString(value, field).trim();
		if (token.length == 0)
			throw 'OCaml runtime source manifest field "$field" must not be empty.';
		return token;
	}

	static function requiredInt(value:Dynamic, field:String):Int {
		final raw:Dynamic = Reflect.field(value, field);
		if (!Std.isOfType(raw, Int))
			throw 'OCaml runtime source manifest field "$field" must be an integer.';
		return cast raw;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
