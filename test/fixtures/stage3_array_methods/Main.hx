/**
	Calls each standard Array method that has no Haxe body on the OCaml target.

	Every line prints a method's return value and the array afterwards, so a
	call that compiles but does nothing produces a visible difference from
	upstream Haxe.
**/
class Main {
	static function show(label:String, values:Array<String>):Void {
		Sys.println(label + " -> " + values.join(","));
	}

	static function showInts(label:String, values:Array<Int>):Void {
		Sys.println(label + " -> " + values.join(","));
	}

	static function main():Void {
		final words = ["x", "y", "z"];
		words.reverse();
		show("reverse", words);

		final popped:Null<String> = words.pop();
		show("pop " + popped, words);

		final shifted:Null<String> = words.shift();
		show("shift " + shifted, words);

		words.unshift("a");
		show("unshift", words);

		words.insert(1, "b");
		show("insert", words);

		final foundBefore = words.contains("b");
		final removed = words.remove("b");
		final missing = words.remove("q");
		show("remove " + removed + " " + missing + " contains " + foundBefore + " " + words.contains("b"), words);

		final emptyPop:Null<String> = [].pop();
		Sys.println("empty pop " + emptyPop);

		final numbers = [3, 1, 2];
		numbers.reverse();
		final lastNumber:Null<Int> = numbers.pop();
		final firstNumber:Null<Int> = numbers.shift();
		numbers.unshift(7);
		numbers.insert(0, 9);
		showInts("ints pop " + lastNumber + " shift " + firstNumber + " remove " + numbers.remove(7) + " contains " + numbers.contains(1), numbers);

		Sys.println("toString " + numbers.toString());
		numbers.resize(4);
		Sys.println("resize " + numbers.length);
	}
}
