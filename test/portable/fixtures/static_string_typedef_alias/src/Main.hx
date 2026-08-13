typedef TextAlias = String;
typedef NullableTextAlias = Null<String>;

class Main {
	static function identity(value:TextAlias):TextAlias {
		return value;
	}

	static function nullableIdentity(value:NullableTextAlias):NullableTextAlias {
		return value;
	}

	static function inferredNullable(flag:Bool):String {
		final value = if (flag) "value" else null;
		return "inferred:" + value;
	}

	static function main():Void {
		Sys.println(Std.string(identity("ok")));
		Sys.println(Std.string(nullableIdentity(null)));
		Sys.println(inferredNullable(false));
	}
}
