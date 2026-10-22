enum Choice {
	Empty;
	Item(value:Int);
}

class Main {
	static function plain(v:Array<Int>):String
		return switch v {
			case [1]: "array";
			case _: "other";
		};

	static function after(v:Array<Int>):String
		return switch v {
			case [1]: "array";
			case null: "null";
			case _: "other";
		};

	static function before(v:Array<Int>):String
		return switch v {
			case null: "null";
			case [1]: "array";
			case _: "other";
		};

	static function empty(v:Array<Int>):String
		return switch v {
			case []: "empty";
			case _: "other";
		};

	static function wild(v:Array<Int>):String
		return switch v {
			case [_]: "one";
			case _: "other";
		};

	static function objectPlain(v:{name:String}):String
		return switch v {
			case {name: "yes"}: "object";
			case _: "other";
		};

	static function objectAfter(v:{name:String}):String
		return switch v {
			case {name: "yes"}: "object";
			case null: "null";
			case _: "other";
		};

	static function nested(v:Array<Array<Int>>):String
		return switch v {
			case [[1]]: "nested";
			case _: "other";
		};

	static function nestedAfter(v:Array<Array<Int>>):String
		return switch v {
			case [[1]]: "nested";
			case [null]: "inner-null";
			case _: "other";
		};

	static function pair(v:Array<Array<Int>>):String
		return switch v {
			case [[1], [2]]: "pair";
			case _: "other";
		};

	static function lengthMismatch(v:Array<Array<Int>>):String
		return switch v {
			case [[1]]: "nested";
			case [null, _]: "two-null";
			case _: "other";
		};

	static function prefixMismatch(v:Array<Array<Int>>):String
		return switch v {
			case [[1], [2]]: "pair";
			case [[3], null]: "second-null";
			case _: "other";
		};

	static function prefixCompatible(v:Array<Array<Int>>):String
		return switch v {
			case [[1], [2]]: "pair";
			case [[1], null]: "second-null";
			case _: "other";
		};

	static function orNull(v:Array<Int>):String
		return switch v {
			case [1] | null: "either";
			case _: "other";
		};

	static function nestedOr(v:Array<Array<Int>>):String
		return switch v {
			case [[1] | null]: "either";
			case _: "other";
		};

	static function enumMatch(v:Choice):String
		return switch v {
			case Item(1): "item";
			case _: "other";
		};

	static function nullCatch():String {
		try {
			plain(null);
			return "none";
		} catch (error:String) {
			return "string:" + error;
		} catch (error:Dynamic) {
			return "dynamic";
		}
	}

	static function reverse(v:{a:Int, b:{tag:String}}):String
		return switch v {
			case {b: {tag: "yes"}, a: 1}: "yes";
			case _: "other";
		};

	static function names(v:{z:Int, a:{tag:String}}):String
		return switch v {
			case {z: 1, a: {tag: "yes"}}: "yes";
			case _: "other";
		};

	static function compatible(v:{a:Int, b:{tag:String}}):String
		return switch v {
			case {a: 1, b: {tag: "yes"}}: "yes";
			case {a: 1, b: null}: "null";
			case _: "other";
		};

	static function effect():Array<Int> {
		Sys.println("scrutinee");
		return null;
	}

	static function main():Void {
		final record:{a:Int, b:{tag:String}} = {a: 3, b: null};
		Sys.println("reverse:" + reverse(record));
		final second:{z:Int, a:{tag:String}} = {z: 3, a: null};
		try {
			Sys.println("names:" + names(second));
		} catch (e:Dynamic) {
			Sys.println("names:throw");
		}
		final third:{a:Int, b:{tag:String}} = {a: 1, b: null};
		Sys.println("compatible:" + compatible(third));
		Sys.println("pair-success:" + pair([[1], [2]]));
		final __hx_switch = "local-root";
		final __hx_pattern_value_0 = "local-child";
		switch effect() {
			case [1]:
				Sys.println("bad");
			case null:
				Sys.println("stmt-null");
			case _:
				Sys.println("bad-default");
		}
		Sys.println(__hx_switch + ":" + __hx_pattern_value_0);

		try {
			Sys.println("enum:" + enumMatch(null));
		} catch (e:Dynamic) {
			Sys.println("enum:throw");
		}
		Sys.println("null-catch:" + nullCatch());

		try {
			Sys.println("length-mismatch:" + lengthMismatch([null]));
		} catch (e:Dynamic) {
			Sys.println("length-mismatch:throw");
		}
		try {
			Sys.println("prefix-mismatch:" + prefixMismatch([[1], null]));
		} catch (e:Dynamic) {
			Sys.println("prefix-mismatch:throw");
		}
		try {
			Sys.println("prefix-compatible:" + prefixCompatible([[1], null]));
		} catch (e:Dynamic) {
			Sys.println("prefix-compatible:throw");
		}
		try {
			Sys.println("or-null:" + orNull(null));
		} catch (e:Dynamic) {
			Sys.println("or-null:throw");
		}
		try {
			Sys.println("nested-or:" + nestedOr([null]));
		} catch (e:Dynamic) {
			Sys.println("nested-or:throw");
		}

		try {
			Sys.println("plain:" + plain(null));
		} catch (e:Dynamic) {
			Sys.println("plain:throw");
		}
		try {
			Sys.println("after:" + after(null));
		} catch (e:Dynamic) {
			Sys.println("after:throw");
		}
		try {
			Sys.println("before:" + before(null));
		} catch (e:Dynamic) {
			Sys.println("before:throw");
		}
		try {
			Sys.println("empty:" + empty(null));
		} catch (e:Dynamic) {
			Sys.println("empty:throw");
		}
		try {
			Sys.println("wild:" + wild(null));
		} catch (e:Dynamic) {
			Sys.println("wild:throw");
		}
		try {
			Sys.println("object:" + objectPlain(null));
		} catch (e:Dynamic) {
			Sys.println("object:throw");
		}
		try {
			Sys.println("object-after:" + objectAfter(null));
		} catch (e:Dynamic) {
			Sys.println("object-after:throw");
		}
		try {
			Sys.println("nested:" + nested([null]));
		} catch (e:Dynamic) {
			Sys.println("nested:throw");
		}
		try {
			Sys.println("nested-after:" + nestedAfter([null]));
		} catch (e:Dynamic) {
			Sys.println("nested-after:throw");
		}
		try {
			Sys.println("pair-first-fails:" + pair([[3], null]));
		} catch (e:Dynamic) {
			Sys.println("pair-first-fails:throw");
		}
		try {
			Sys.println("pair-first-length:" + pair([[], null]));
		} catch (e:Dynamic) {
			Sys.println("pair-first-length:throw");
		}
	}
}
