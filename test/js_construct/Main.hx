import js.Syntax as NativeSyntax;

/** An ordinary class proves that construct invokes the authored constructor. */
class Widget {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** A same-spelled method must remain a normal call. */
class Other {
	public static function construct(value:Int):Int {
		return value + 1;
	}
}

/** Host syntax is limited to the allocation under test and the stdout observer. */
class Main {
	static var order:String = "";

	static function choose():Class<Widget> {
		order += "c";
		return Widget;
	}

	static function argument():Int {
		order += "a";
		return 7;
	}

	static function main():Void {
		final values:Array<String> = NativeSyntax.construct(Array, 1);
		values[0] = "ok";
		NativeSyntax.code("console.log({0})", values[0]);
		final widget = NativeSyntax.construct(choose(), argument());
		NativeSyntax.code("console.log({0})", widget.value);
		NativeSyntax.code("console.log({0})", order);
		final named:Array<Int> = NativeSyntax.construct("Array", 3);
		NativeSyntax.code("console.log({0})", named.length);
		final qualified:Array<Int> = NativeSyntax.construct("globalThis.Array", 4);
		NativeSyntax.code("console.log({0})", qualified.length);
		final args = [1, 2];
		final spread:Array<Int> = NativeSyntax.construct(Array, ...args);
		NativeSyntax.code("console.log({0})", spread.length);
		NativeSyntax.code("console.log({0})", Other.construct(8));
	}
}
