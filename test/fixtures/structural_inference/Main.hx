/** Generic method results must retain each parameter occurrence inside nested records. */
class Main {
	static function wrap<T>(value:T):{item:T, nested:{item:T}} {
		return {item: value, nested: {item: value}};
	}

	static function main():Void {
		final words = wrap("ok");
		final numbers = wrap(7);
		final contextual:{item:Null<String>} = empty();
		Sys.println(words.item);
		Sys.println(words.nested.item);
		Sys.println(numbers.item);
		Sys.println(numbers.nested.item);
		Sys.println(contextual.item == null);
	}

	static function empty<T>():{item:Null<T>} {
		return {item: null};
	}
}
