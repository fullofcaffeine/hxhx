package hxhx;

import haxe.io.Path;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.runtime.NullableRuntimeString;
import backend.OcamlProfile;

private typedef HaxelibSpec = LibraryResolver.LibrarySpec;

/**
	Stage3 library, classpath, and define setup helpers.

	Why
	- `Stage3Compiler` needs to orchestrate parse/type/emit, but a large part of
	  `runOne` was request setup: library metadata, macro host classpaths, resolver
	  classpaths, and conditional-compilation defines.

	What
	- Resolves requested libraries through the repo resolver.
	- Collects library-provided defines and macro expressions.
	- Builds macro-host and project classpath lists.
	- Builds the effective define map consumed by resolver/typer/backend stages.

	How
	- Preserve the existing ordering and deduplication rules.
	- Keep macro-state reads explicit because macros may mutate classpaths, defines,
	  and included modules before resolver setup runs.
**/
class Stage3SetupSupport {
	static inline function trim(value:String):String {
		return NullableRuntimeString.trimToEmpty(value);
	}

	public static function resolveLibraries(parsedLibs:Array<String>, cwd:String):Array<HaxelibSpec> {
		final seen = new Map<String, Bool>();
		final out = new Array<HaxelibSpec>();
		for (lib in parsedLibs)
			out.push(LibraryResolver.resolve(lib, cwd, seen, 0));
		return out;
	}

	public static function collectLibraryDefines(libsResolved:Array<HaxelibSpec>):Array<String> {
		final out = new Array<String>();
		for (s in libsResolved)
			for (d in s.defines)
				if (out.indexOf(d) == -1)
					out.push(d);
		return out;
	}

	public static function collectLibraryMacros(libsResolved:Array<HaxelibSpec>):Array<String> {
		final out = new Array<String>();
		for (s in libsResolved)
			for (m in s.macros)
				if (out.indexOf(m) == -1)
					out.push(m);
		return out;
	}

	public static function collectMacroStdPaths(cwd:String):Array<String> {
		final out = new Array<String>();
		final envStd = trim(Sys.getEnv("HAXE_STD_PATH"));
		if (envStd.length > 0)
			out.push(Path.normalize(envStd));
		final inferredStd = Stage1Args.inferStdRootForCwd(cwd);
		if (inferredStd.length > 0) {
			final normalized = Path.normalize(inferredStd);
			var seen = false;
			for (cp in out) {
				if (Path.normalize(cp) == normalized) {
					seen = true;
					break;
				}
			}
			if (!seen)
				out.push(inferredStd);
		}
		return out;
	}

	public static function macroHostClassPaths(parsedClassPaths:Array<String>, libsResolved:Array<HaxelibSpec>, cwd:String):Array<String> {
		final base = parsedClassPaths.map(cp -> Stage3PathSupport.absFromCwd(cwd, cp));
		final libs = new Array<String>();
		for (s in libsResolved)
			for (p in s.classPaths)
				libs.push(Stage3PathSupport.absFromCwd(cwd, p));
		final outAll = base.concat(libs);

		final stdCp = trim(Sys.getEnv("HAXE_STD_PATH"));
		if (stdCp.length == 0)
			return outAll;

		final stdAbs = Path.normalize(stdCp);
		final filtered = new Array<String>();
		for (cp in outAll) {
			if (Path.normalize(cp) != stdAbs)
				filtered.push(cp);
		}
		return filtered;
	}

	public static function projectClassPaths(parsedClassPaths:Array<String>, libsResolved:Array<HaxelibSpec>, cwd:String):Array<String> {
		final base = parsedClassPaths.map(cp -> Stage3PathSupport.absFromCwd(cwd, cp));
		final libs = new Array<String>();
		for (s in libsResolved)
			for (p in s.classPaths)
				libs.push(Stage3PathSupport.absFromCwd(cwd, p));
		final extra = hxhx.macro.MacroState.listClassPaths().map(cp -> Stage3PathSupport.absFromCwd(cwd, cp));
		final out = base.concat(libs).concat(extra);
		final generatedHxDir = hxhx.macro.MacroState.getGeneratedHxDir();
		if (generatedHxDir != null && generatedHxDir.length > 0) {
			final generatedNorm = Path.normalize(generatedHxDir);
			var hasGeneratedDir = false;
			for (cp in out) {
				if (Path.normalize(cp) == generatedNorm) {
					hasGeneratedDir = true;
					break;
				}
			}
			if (!hasGeneratedDir)
				out.push(generatedHxDir);
		}

		final inferredStd = Stage1Args.inferStdRootForCwd(cwd);
		if (inferredStd.length > 0) {
			final inferredNorm = Path.normalize(inferredStd);
			var hasStd = false;
			for (cp in out) {
				if (Path.normalize(cp) == inferredNorm) {
					hasStd = true;
					break;
				}
			}
			if (!hasStd)
				out.push(inferredStd);
		}
		return ResolverStage.withImplicitCwdClassPath(out, cwd);
	}

	public static function buildDefinesMap(allDefines:Array<String>, backendTargetDefine:String, backendId:String):haxe.ds.StringMap<String> {
		final definesMap = HxDefineMap.fromRawDefines(allDefines);
		definesMap.set("sys", "1");
		definesMap.set(backendTargetDefine, "1");
		for (n in hxhx.macro.MacroState.listDefineNames()) {
			definesMap.set(n, hxhx.macro.MacroState.definedValue(n));
		}
		if (backendId == "ocaml-stage3") {
			final profile = OcamlProfile.fromDefineValue(definesMap.get("ocaml_profile"));
			definesMap.set("ocaml_profile", OcamlProfile.toDefineValue(profile));
		}
		return definesMap;
	}
}
