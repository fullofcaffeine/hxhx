/**
	Builds an exact in-memory identity from compiler input strings.

	Each value is preceded by its character length, so different input lists cannot
	produce the same identity merely because they contain separator characters.
	The native server uses these identities as map keys while it is running. They
	are intentionally not cryptographic digests and are not a persistent cache
	format; a future on-disk cache must use a measured native hashing adapter and
	retain enough input evidence to reject collisions.
**/
class CompilerCacheIdentity {
	public static function encode(values:Array<Null<String>>):String {
		final out = new StringBuf();
		if (values == null) {
			out.add("-1:");
			return out.toString();
		}
		out.add(values.length);
		out.add(":");
		for (value in values) {
			if (value == null) {
				out.add("-1:");
				continue;
			}
			out.add(value.length);
			out.add(":");
			out.add(value);
		}
		return out.toString();
	}
}
