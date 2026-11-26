class Something {
	public static function somefunc()
		return 42;
}

/** An annotated Class<T> is not the class's statics: upstream reports `Class<Something> has no field somefunc`. */
class Wrong {
	static function main() {
		var s:Class<Something> = Something;
		Sys.println(s.somefunc());
	}
}
