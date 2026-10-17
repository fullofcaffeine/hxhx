/** Source bytes embedded in the compiler, named relative to its target standard-library bundle. */
typedef BundledSourceFile = {
	final name:String;
	final content:String;
}

private final files:Array<BundledSourceFile> = CompilerBundledSourcesMacro.files();
private final namespace = "/__hxhx_bundled_sources__/";

private final root = namespace + haxe.crypto.Sha256.encode(CompilerCacheIdentity.encode([
	for (file in files)
		CompilerCacheIdentity.encode([file.name, file.content])
]));

/**
	Return the immutable source root for a supported target. Its content identity
	travels through ordinary classpath lookup and parser-cache keys. Runtime reads
	use these embedded bytes, never a build-machine path or the source checkout.
 */
function targetRoot(target:String):Null<String> {
	return target == "cpp" ? root + "/cpp/_std" : null;
}

/** Reserve the whole namespace so a stale bundle identity cannot fall back to disk. */
function owns(path:String):Bool
	return path != null && StringTools.startsWith(path, namespace);

/** Return a fresh byte buffer so callers cannot modify the embedded source snapshot. */
function readBytes(path:String):Null<haxe.io.Bytes> {
	for (file in files)
		if (path == root + "/" + file.name)
			return haxe.io.Bytes.ofString(file.content);
	return null;
}

/** Exact-case directory entries let the ordinary module resolver preserve lookup policy. */
function readDirectory(path:String):Array<String> {
	final prefix = StringTools.endsWith(path, "/") ? path : path + "/";
	final entries = new Array<String>();
	for (file in files) {
		final name = root + "/" + file.name;
		if (!StringTools.startsWith(name, prefix))
			continue;
		final rest = name.substr(prefix.length);
		final slash = rest.indexOf("/");
		final entry = slash == -1 ? rest : rest.substr(0, slash);
		if (entry.length > 0 && entries.indexOf(entry) == -1)
			entries.push(entry);
	}
	entries.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
	return entries;
}

/** Test membership without allocating or decoding the source. */
function isFile(path:String):Bool {
	for (file in files)
		if (path == root + "/" + file.name)
			return true;
	return false;
}
