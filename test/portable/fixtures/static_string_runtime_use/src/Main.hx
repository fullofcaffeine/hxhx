class Main {
	static final events:Array<String> = [];

	static function nullable(label:String):Null<String> {
		events.push(label);
		return null;
	}

	static function text(label:String, value:String):String {
		events.push(label);
		return value;
	}

	static function pureConcat(left:String, right:String):String {
		return left + right;
	}

	static function nullableInt(value:Null<Int>):Null<Int> {
		return value;
	}

	static function nullableFloat(value:Null<Float>):Null<Float> {
		return value;
	}

	static function nullableBool(value:Null<Bool>):Null<Bool> {
		return value;
	}

	static function main():Void {
		Sys.println("std=" + Std.string(nullable("std")));
		Sys.println("concat=" + text("concat-left", "L") + nullable("concat-right"));

		var assigned:Null<String> = nullable("assign-initial");
		assigned += text("assign-right", "R");
		Sys.println("assigned=" + assigned);

		var dynamicAssigned:Dynamic = 7;
		dynamicAssigned += text("dynamic-assign-right", "D");
		Sys.println("dynamic-assigned=" + dynamicAssigned);

		final record:Dynamic = {answer: 42};
		Sys.println("field=" + Reflect.field(record, text("field-name", "answer")));

		Sys.println("direct-int=" + Std.string(nullableInt(null)));
		Sys.println("concat-int=" + nullableInt(null) + "/" + nullableInt(7));
		Sys.println("direct-float=" + Std.string(nullableFloat(null)));
		Sys.println("concat-float=" + nullableFloat(null) + "/" + nullableFloat(2.5));
		Sys.println("direct-bool=" + Std.string(nullableBool(null)));
		Sys.println("concat-bool=" + nullableBool(null) + "/" + nullableBool(true));
		Sys.println("events=" + events.join(","));
	}
}
