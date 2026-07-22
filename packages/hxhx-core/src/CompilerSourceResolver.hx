import haxe.io.Path;

/**
	Resolves Haxe modules against ordered class paths and records why the answer is valid.

	The resolver preserves Haxe's class-path precedence and exact filename-case
	checks. It also supports secondary types, where `pack.Mod.SubType` may be
	declared in `pack/Mod.hx`. Each relevant exact filename observation is part of
	the returned revision, so a server cache cannot overlook a new file that
	shadows the previously selected module.
**/
class CompilerSourceResolver {
	public static function resolve(readDirectory:(path:String) -> Array<String>, isFile:(path:String) -> Bool, classPaths:Array<String>,
			modulePath:String):CompilerModuleResolution {
		final effectiveClassPaths = classPaths == null ? [] : classPaths;
		final normalizedModulePath = modulePath == null ? "" : StringTools.trim(modulePath);
		final lookupIdentity = CompilerCacheIdentity.encode(["module-lookup-v3", normalizedModulePath]);
		final observations = new Array<String>();
		observations.push("lookup=" + lookupIdentity);

		if (normalizedModulePath.length == 0)
			return missing(lookupIdentity, observations);
		final parts = normalizedModulePath.split(".");
		if (parts.length == 0)
			return missing(lookupIdentity, observations);

		final direct = parts.join("/") + ".hx";
		final directResult = find(readDirectory, isFile, effectiveClassPaths, direct, false, lookupIdentity, observations);
		if (directResult != null)
			return directResult;

		// A Haxe import can name a secondary type stored in its module file:
		// pack.Mod.SubType resolves through pack/Mod.hx when no direct file exists.
		if (parts.length >= 2) {
			final fallback = parts.slice(0, parts.length - 1).join("/") + ".hx";
			final fallbackResult = find(readDirectory, isFile, effectiveClassPaths, fallback, true, lookupIdentity, observations);
			if (fallbackResult != null)
				return fallbackResult;
		}

		return missing(lookupIdentity, observations);
	}

	static function find(readDirectory:(path:String) -> Array<String>, isFile:(path:String) -> Bool, classPaths:Array<String>, relativePath:String,
			usedFallback:Bool, lookupIdentity:String, observations:Array<String>):Null<CompilerModuleResolution> {
		for (index in 0...classPaths.length) {
			final classPath = classPaths[index];
			final candidate = Path.join([classPath, relativePath]);
			final candidateDirectory = Path.directory(candidate);
			final directory = candidateDirectory == null || candidateDirectory.length == 0 ? "." : candidateDirectory;
			final basename = Path.withoutDirectory(candidate);
			final entries = readDirectory(directory);
			entries.sort(compareStrings);
			observations.push('candidate=${usedFallback ? "fallback" : "direct"}:$index:$basename');
			if (!contains(entries, basename)) {
				observations.push("kind=missing");
				continue;
			}
			final candidateIsFile = isFile(candidate);
			observations.push("kind=" + (candidateIsFile ? "file" : "non-file"));
			if (!candidateIsFile)
				continue;
			observations.push("selected-normalized=" + normalizePath(candidate));
			// Preserve the returned spelling too. Equivalent class-path spellings
			// must not reuse a result that carries a previous request's path text.
			observations.push("selected-path=" + candidate);
			return new CompilerModuleResolution(lookupIdentity, observationRevision(observations), candidate, index, usedFallback);
		}
		return null;
	}

	static function missing(lookupIdentity:String, observations:Array<String>):CompilerModuleResolution {
		observations.push("selected=<missing>");
		return new CompilerModuleResolution(lookupIdentity, observationRevision(observations), null, -1, false);
	}

	static function normalizePath(path:String):String {
		if (path == null || path.length == 0)
			return "";
		return Path.normalize(sys.FileSystem.absolutePath(path));
	}

	static function contains(values:Array<String>, expected:String):Bool {
		for (value in values)
			if (value == expected)
				return true;
		return false;
	}

	static function observationRevision(observations:Array<String>):String {
		final values = new Array<Null<String>>();
		values.push("module-observations-v1");
		for (observation in observations)
			values.push(observation);
		return CompilerCacheIdentity.encode(values);
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
