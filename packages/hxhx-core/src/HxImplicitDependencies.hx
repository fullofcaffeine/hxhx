/**
	Find qualified type candidates when module loading cannot yet rely on typed references.

	Both eager resolution and lazy loading use this heuristic. Comments cannot add candidates,
	and whitespace between path tokens is allowed. String contents can still over-approximate
	dependencies; this helper does not claim full type-driven module resolution.
**/
function qualifiedTypePaths(source:String, ?defines:haxe.ds.StringMap<String>):Array<String> {
	if (source == null || source.length == 0)
		return [];

	final lines = HxLexer.maskComments(source).split("\n");
	for (i in 0...lines.length) {
		// Keep the existing metadata exclusion: macro entrypoints do not belong to the
		// ordinary compilation graph. A separator prevents a path spanning an excluded line.
		if (StringTools.startsWith(StringTools.trim(lines[i]), "@:"))
			lines[i] = ";";
	}
	final text = lines.join("\n");
	final candidates = new haxe.ds.StringMap<Bool>();
	final paths = ~/\b(([A-Za-z_][A-Za-z0-9_]*\s*\.\s*)+[A-Z][A-Za-z0-9_]*)\b/g;
	final whitespace = ~/\s+/g;
	var pos = 0;
	while (paths.matchSub(text, pos, -1)) {
		final dep = whitespace.replace(paths.matched(1), "");
		if (!HxConditionalCompilation.isInactiveTargetQualifiedTypePath(dep, defines))
			candidates.set(dep, true);
		final matched = paths.matchedPos();
		pos = matched.pos + matched.len;
	}
	final out = [for (dep in candidates.keys()) dep];
	out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
	return out;
}
