/**
	Repo-owned upstream Haxe oracle cases for the Cpp `TestJson` frontier.

	These cases intentionally pin observable behavior only. They do not copy
	upstream tests, and they do not imply Cpp support is implemented.
**/
class Main {
	static function emit(id:String, field:String, value:String):Void {
		final line = id + "|" + field + "|" + value;
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function codeUnits(value:String):String {
		final out:Array<String> = [];
		for (i in 0...value.length) {
			out.push(Std.string(value.charCodeAt(i)));
		}
		return out.join(",");
	}

	static function summarizeParsedObject(text:String):String {
		final parsed:Dynamic = haxe.Json.parse(text);
		final a:Array<Dynamic> = cast Reflect.field(parsed, "a");
		return Std.string(Reflect.field(parsed, "x")) + ":" + Std.string(Reflect.field(parsed, "y")) + ":" + Std.string(a.length) + ":" + Std.string(a[0])
			+ ":" + codeUnits(Std.string(a[1]));
	}

	static function summarizeDynamic(value:Dynamic):String {
		if (value == null) {
			return "null";
		}
		if (Std.isOfType(value, String)) {
			return "string:" + codeUnits(cast value);
		}
		if (Std.isOfType(value, Array)) {
			final array:Array<Dynamic> = cast value;
			return "array:" + array.length + ":" + array.map(function(item) return summarizeDynamic(item)).join(",");
		}
		return Type.typeof(value).getName() + ":" + Std.string(value);
	}

	static function jsonId(label:String, value:Dynamic, ?pos:haxe.PosInfos):Void {
		emit("json-id-optional-pos-01:" + label, "pos", Std.string(pos != null));
		emit("json-id-optional-pos-01:" + label, "round", summarizeDynamic(haxe.Json.parse(haxe.Json.stringify(value))));
	}

	static function deepId(label:String, value:Dynamic):Void {
		final text = haxe.Json.stringify(value);
		emit("json-deep-struct-01:" + label, "json", text);
		emit("json-deep-struct-01:" + label, "round", haxe.Json.stringify(haxe.Json.parse(text)));
	}

	static function invalidJson(label:String, text:String):Void {
		emit("json-invalid-01:" + label, "input", text);
		try {
			final parsed:Dynamic = haxe.Json.parse(text);
			emit("json-invalid-01:" + label, "result", summarizeDynamic(parsed));
		} catch (e:Dynamic) {
			emit("json-invalid-01:" + label, "error", Std.string(e));
		}
	}

	static function main():Void {
		final structural = haxe.Json.stringify({
			x: -4500,
			y: 1.456,
			a: ["hello", "wor'\"\n\t\rd"]
		});
		emit("json-struct-01", "json", structural);
		emit("json-struct-01", "summary", summarizeParsedObject(structural));

		jsonId("true", true);
		jsonId("null", null);
		jsonId("finite", 0.15461);
		jsonId("exponent", -1e-10);
		jsonId("string-escapes", "he\n\r\t\\\\llo");

		deepId("field", {field: 4});
		deepId("nested-null", {test: {nested: null}});
		final mix:Array<Dynamic> = [1, 2, 3, "str"];
		deepId("mixed-array", {array: mix});

		final unicode:String = haxe.Json.parse("\"\\u00E9\"");
		emit("json-unicode-01", "length", Std.string(unicode.length));
		emit("json-unicode-01", "codes", codeUnits(unicode));

		emit("json-finite-format-01:small", "json", haxe.Json.stringify(0.15461));
		emit("json-finite-format-01:negative", "json", haxe.Json.stringify(-485.15461));
		emit("json-finite-format-01:large", "json", haxe.Json.stringify(1e10));
		emit("json-finite-format-01:exponent", "json", haxe.Json.stringify(-1e-10));
		emit("json-signed-zero-01:positive", "json", haxe.Json.stringify(0.0));
		emit("json-signed-zero-01:negative", "json", haxe.Json.stringify(-0.0));

		emit("json-nonfinite-01:posinf", "json", haxe.Json.stringify(Math.POSITIVE_INFINITY));
		emit("json-nonfinite-01:neginf", "json", haxe.Json.stringify(Math.NEGATIVE_INFINITY));
		emit("json-nonfinite-01:nan", "json", haxe.Json.stringify(Math.NaN));
		emit("json-nonfinite-01:posinf", "printer", haxe.format.JsonPrinter.print(Math.POSITIVE_INFINITY));
		emit("json-nonfinite-01:neginf", "printer", haxe.format.JsonPrinter.print(Math.NEGATIVE_INFINITY));
		emit("json-nonfinite-01:nan", "printer", haxe.format.JsonPrinter.print(Math.NaN));

		emit("json-printer-function-01:function", "printer", haxe.format.JsonPrinter.print(function() {}));
		emit("json-printer-function-01:object-field", "printer", haxe.format.JsonPrinter.print({a: function() {}, b: 1}));

		invalidJson("triple-quote-key", "{\"\"\"a\": 1}");
	}
}
