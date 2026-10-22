/** An ordinary Haxe factory consumes the same generic class alias at two concrete types. */
class Factory {
	public static function create<T>(cls:Class<Array<T>>, value:T):Array<T> {
		if (cls != Array)
			throw "wrong class";
		return [value];
	}
}

/** Native syntax is limited to the stdout observer; class and array behavior is authored Haxe. */
class Main {
	static function main():Void {
		final cls = Array;
		final strings:Array<String> = Factory.create(cls, "ok");
		final numbers:Array<Int> = Factory.create(cls, 7);
		js.Syntax.code("console.log({0})", strings[0]);
		js.Syntax.code("console.log({0})", numbers[0]);
		js.Syntax.code("console.log({0})", cls == Array);
	}
}
