/** Checks copied values, width subtyping, optional fields, and mutation through an alias. */
class Main {
	static function main():Void {
		final source = {value: 7, label: "kept", extra: true};
		final copied = First.copy(source);
		Sys.println(copied.value);
		Sys.println(copied.label == null);
		final alias = Second.update(source);
		Sys.println(source.value);
		Sys.println(alias == source);
		Sys.println(alias.label);
		Sys.println(source.extra);
		Sys.println(First.withToken(source, new Token(3)).value);
	}
}
