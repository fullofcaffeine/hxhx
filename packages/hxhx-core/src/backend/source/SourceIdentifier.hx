package backend.source;

/**
	Target-neutral source-language identifier spelling.

	This helper replaces characters outside the shared ASCII identifier subset.
	Target-specific reserved words and namespace rules belong to the target
	module that consumes this base spelling.
**/
class SourceIdentifier {
	/**
		Returns the shared source-target spelling for one identifier.

		Null and empty inputs retain the historical `Main` fallback. Callers that
		need a different fallback must decide that before calling this helper.
	**/
	public static function sanitize(name:String):String {
		final source = name == null || name.length == 0 ? "Main" : name;
		final output = new StringBuf();
		for (index in 0...source.length) {
			final character = source.charAt(index);
			final allowed = (character >= "A" && character <= "Z")
				|| (character >= "a" && character <= "z")
				|| (character >= "0" && character <= "9")
				|| character == "_";
			output.add(allowed ? character : "_");
		}
		return output.toString();
	}
}
