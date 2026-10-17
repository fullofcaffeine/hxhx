/** The source patterns exercise nested enum payloads and structural records. */
enum TextValue {
	Text(value:String);
	IntText(value:String);
	FloatText(value:String);
}

enum Operator {
	In;
}

enum Expression {
	Wrap(value:TextValue);
	Group(value:{value:Expression});
	Raw(value:{value:Expression});
	Pick(ignored:Int, name:String);
	At(ignored:Int, value:{value:Expression});
	InOp(op:Operator, ignored:Int, value:{value:Expression, pos:Int});
	Other;
}

enum NullableValue {
	A(value:Null<String>);
}

/** Run the original switch expressions with independently stated runtime expectations. */
class Main {
	static var inputCalls:Int = 0;

	/** Observe input evaluation separately from integer parsing. */
	static function readInput(value:String):String {
		inputCalls++;
		return value;
	}

	/** The same nullable results must survive ordinary calls and extractor bindings. */
	static function integerParsing():Void {
		final inputs:Array<String> = [
			null,
			"",
			" ",
			"invalid",
			"23",
			"-17",
			"+19",
			" 42tail",
			"010",
			"0x2a",
			"0X2A",
			"-0x2a",
			"+0x2a",
			"0x",
			"1.5",
			"0b11",
			"Infinity",
			"NaN"
		];
		final expected:Array<Null<Int>> = [
			null, null, null, null, 23, -17, 19, 42, 10, 42, 42, -42, 42, null, 1, 0, null, null
		];
		for (index in 0...inputs.length) {
			if (Std.parseInt(readInput(inputs[index])) != expected[index] || inputCalls != index * 2 + 1)
				throw "ordinary integer parsing or input evaluation";
			if (qualifiedExtractorPattern(["exitCode", readInput(inputs[index])]) != expected[index] || inputCalls != index * 2 + 2)
				throw "extractor integer parsing or input evaluation";
		}
	}

	static function simple(mode:String):Int
		return switch (mode) {
			case "a": 1;
			case "b" | "c": 2;
			default: 9;
		};

	static function bind(mode:Int):Int
		return switch (mode) {
			case value: value + 1;
		};

	static function thrown(value:String):String
		return switch (value) {
			case label: throw 'unknown value $label';
		};

	static function run(path:String):Void
		throw path;

	static function tryCatchThrow(path:String, name:String):Void {
		try {
			run(path);
		} catch (e:Dynamic) {
			trace(e);
			trace(name);
			throw e;
		}
	}

	static function objectPattern(payload:{expr:Expression}):String
		return switch (payload.expr) {
			case Wrap(Text(s)): s;
			case Group({value: Wrap(Text(s))}) | Raw({value: Wrap(Text(s))}): s;
			case Pick(_, name): name;
			case At(_, {value: Wrap(IntText(i) | FloatText(i))}): Std.string(i);
			case InOp(In, _, {value: inner, pos: _}): Std.string(inner);
			case _: "none";
		};

	static function capturePattern(payload:Expression):String
		return switch payload {
			case Wrap(captured = (Text("hello") | IntText("9"))): Std.string(captured);
			case _: "none";
		};

	static function arrayPattern(values:Array<String>):String
		return switch values {
			case []: "empty";
			case [one]: one;
			case [left, right]: left + right;
			case _: "many";
		};

	static function guardedPattern(values:Array<Int>):String
		return switch values {
			case var rest if (rest.length == 3): Std.string(rest.length);
			case _: "other";
		};

	static function groupedPattern(v:Int):String
		return switch v {
			case 1, 2, 3: "small";
			case val = (4 | 5 | 6) if (val == 5): "middle";
			case var x: "_";
		};

	static function qualifiedExtractorPattern(args:Array<String>):Null<Int>
		return switch args {
			case ["exitCode", Std.parseInt(_) => code]: code;
			case _: 0;
		};

	static function sliceExtractorPattern(args:Array<String>):Int
		return switch args {
			case _.slice(0, 1) => ["putEnv"]: 1;
			case _: 0;
		};

	static function switchIfElseSemicolon(v:NullableValue):String
		return switch v {
			case A(x): if (x == null) "null"; else "not null";
		};

	static function emptyCase(value:Bool):Void {
		switch value {
			case true:
			case false:
		}
	}

	static function main():Void {
		QuotationCases.run();
		integerParsing();
		if (simple("a") != 1 || simple("b") != 2 || simple("c") != 2 || simple("z") != 9 || bind(6) != 7)
			throw "literal, alternative, default, or binding";
		var message = "";
		try {
			thrown("red");
		} catch (error:String) {
			message = error;
		}
		if (message != "unknown value red")
			throw "throw branch interpolation";
		try {
			tryCatchThrow("failure", "observer");
		} catch (error:String) {
			message = error;
		}
		if (message != "failure")
			throw "final rethrow";
		if (objectPattern({expr: Wrap(Text("direct"))}) != "direct"
			|| objectPattern({expr: Group({value: Wrap(Text("group"))})}) != "group"
			|| objectPattern({expr: Raw({value: Wrap(Text("raw"))})}) != "raw"
			|| objectPattern({expr: Pick(0, "picked")}) != "picked"
			|| objectPattern({expr: At(0, {value: Wrap(IntText("7"))})}) != "7"
			|| objectPattern({expr: At(0, {value: Wrap(FloatText("2.5"))})}) != "2.5"
			|| objectPattern({expr: InOp(In, 0, {value: Wrap(Text("inside")), pos: 1})}) != "Wrap(Text(inside))"
			|| objectPattern({expr: Other}) != "none")
			throw "nested constructor, object, or alternative";
		if (capturePattern(Wrap(Text("hello"))) != "Text(hello)"
			|| capturePattern(Wrap(IntText("9"))) != "IntText(9)"
			|| capturePattern(Wrap(Text("miss"))) != "none"
			|| capturePattern(Other) != "none")
			throw "captured alternative or literal restriction";
		if (arrayPattern([]) != "empty" || arrayPattern(["a"]) != "a" || arrayPattern(["a", "b"]) != "ab" || arrayPattern(["a", "b", "c"]) != "many")
			throw "array pattern length or binding";
		if (guardedPattern([1, 2, 3]) != "3" || guardedPattern([1, 2]) != "other")
			throw "guarded capture";
		if (groupedPattern(1) != "small" || groupedPattern(2) != "small" || groupedPattern(3) != "small" || groupedPattern(5) != "middle"
			|| groupedPattern(4) != "_" || groupedPattern(6) != "_" || groupedPattern(9) != "_")
			throw "grouped alternatives or capture guard";
		if (qualifiedExtractorPattern(["exitCode", "23"]) != 23
			|| qualifiedExtractorPattern(["exitCode", "invalid"]) != null
			|| qualifiedExtractorPattern(["other", "23"]) != 0
			|| qualifiedExtractorPattern([]) != 0)
			throw "qualified extractor";
		if (sliceExtractorPattern(["putEnv", "key"]) != 1 || sliceExtractorPattern(["other"]) != 0 || sliceExtractorPattern([]) != 0)
			throw "slice extractor";
		if (switchIfElseSemicolon(A(null)) != "null" || switchIfElseSemicolon(A("x")) != "not null")
			throw "semicolon before else";
		emptyCase(true);
		emptyCase(false);
	}
}
