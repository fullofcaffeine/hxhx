/**
	String interpolation as Haxe 4.3.7 parses it: a single-quoted string with `$` stays one
	`CString(text, SingleQuotes)`, and typing expands it later.
**/
class Main {
	static function greet(name:String, count:Int):String {
		return 'hello $name, you have ${count + 1} messages';
	}

	static function nested(items:Array<Int>):String {
		return 'first=${items[0]} size=${items.length} sum=${items[0] + items[1]}';
	}

	static function escapes(price:Int):String {
		var plain = 'no interpolation here';
		var dollar = 'cost: $$${price}';
		return plain + "|" + dollar + '\t$price';
	}

	static function code():Int {
		return 'a'.code + 'b'.code;
	}

	static function main() {
		Sys.println(greet("ada", 2));
		Sys.println(nested([3, 4]));
		Sys.println(escapes(7));
		Sys.println(code());
	}
}
