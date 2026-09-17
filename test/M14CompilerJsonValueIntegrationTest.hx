import hxhx.CompilerJsonParser;
import hxhx.CompilerJsonValue;

/** Checks JSON value kinds, nested storage, and deterministic syntax diagnostics. */
class M14CompilerJsonValueIntegrationTest {
	static function assertTrue(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function expectSyntaxError(input:String, expected:String):Void {
		try {
			CompilerJsonParser.parse(input);
		} catch (error:haxe.Exception) {
			assertTrue(error.message == expected, "unexpected JSON diagnostic: " + error.message);
			return;
		}
		throw "expected invalid JSON: " + input;
	}

	/** Shared by the standalone JSON check and the plugin-manifest integration. */
	public static function run():Void {
		final numbers = switch (CompilerJsonParser.parse('{\n "int" : 7,\n "float" : 1.5, "exponent" : 2e3, "negative" : -4\n}')) {
			case JsonObject(fields): fields;
			case _: throw "expected a JSON object";
		}
		assertTrue(switch (numbers.get("int")) {
			case JsonInt(7): true;
			case _: false;
		}, "integer token lost its Int variant");
		assertTrue(switch (numbers.get("float")) {
			case JsonFloat(1.5): true;
			case _: false;
		}, "fraction token lost its Float variant");
		assertTrue(switch (numbers.get("exponent")) {
			case JsonFloat(2000.0): true;
			case _: false;
		}, "exponent token lost its Float variant");
		assertTrue(switch (numbers.get("negative")) {
			case JsonInt(-4): true;
			case _: false;
		}, "negative integer changed");

		final nested = CompilerJsonParser.parse(' [null,true,false,"a\\n\\u0041",{"key":1,"key":2,"present":null}] \n');
		switch (nested) {
			case JsonArray([
				JsonNull,
				JsonBool(true),
				JsonBool(false),
				JsonString("a\nA"),
				JsonObject(fields)
			]):
				assertTrue(switch (fields.get("key")) {
					case JsonInt(2): true;
					case _: false;
				}, "duplicate object keys must keep the last value");
				assertTrue(fields.exists("present") && !fields.exists("missing"), "absent and null fields must remain distinct");
				assertTrue(switch (fields.get("present")) {
					case JsonNull: true;
					case _: false;
				}, "explicit null field lost its value");
			case _:
				throw "nested JSON kinds or escaped text changed";
		}

		expectSyntaxError("{", "unexpected token at position 1");
		expectSyntaxError("[", "unexpected EOF at position 1");
		expectSyntaxError("[1,]", "invalid token at position 3");
		expectSyntaxError("{}x", "unexpected trailing token at position 2");
		expectSyntaxError('"\\u00xx"', "invalid unicode escape at position 6");
	}

	static function main():Void {
		run();
		Sys.println("OK compiler JSON values");
	}
}
