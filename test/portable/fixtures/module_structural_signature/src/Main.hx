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
		Sys.println(First.scopes(source)[0][0].value);
		Sys.println(First.scopes(source, null)[0][0].value);
		final groups = [[new Token(4)]];
		final returned = First.scopes(source, groups);
		Sys.println(returned == groups);
		returned[0].push(new Token(5));
		Sys.println(groups[0].length);
		Sys.println(First.scopes(source, []).length);
	}
}
