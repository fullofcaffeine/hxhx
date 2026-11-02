/**
	Uses structure types written in place, in the typedef declaration form,
	with both object literals and class instances.

	Each value is called directly, stored in a local, and passed to a
	function, so a method that cannot be found or called shows up as a
	changed line or a crash.
**/
typedef Reader = {function value():Int;}

class Answer {
	public function new() {}

	public function value():Int
		return 7;

	public function add(a:Int, b:Int):Int
		return a + b + 100;
}

class LateAnswer extends Answer {
	public var count:Int = 3;

	override public function value():Int
		return 70;
}

class Main {
	static function provide():{function value():Int;}
		return new Answer();

	static function literal():{function value():Int;}
		return {value: () -> 8};

	static function adder():{function add(a:Int, b:Int):Int;}
		return {add: (a:Int, b:Int) -> a + b};

	static function holder():{var value:Void->Int;}
		return {value: () -> 9};

	static function read(source:{function value():Int;}):Int
		return source.value();

	static function sum(source:{function add(a:Int, b:Int):Int;}, a:Int, b:Int):Int
		return source.add(a, b);

	static function named():Reader
		return new LateAnswer();

	static function main():Void {
		if (provide().value() != 7)
			throw "result";
		Sys.println("ok");

		Sys.println("literal: " + literal().value());
		Sys.println("adder: " + adder().add(2, 3));
		Sys.println("holder: " + holder().value());

		final fromClass = provide();
		final stored = fromClass.value;
		Sys.println("stored class method: " + stored());
		final fromLiteral = literal();
		final storedLiteral = fromLiteral.value;
		Sys.println("stored literal method: " + storedLiteral());

		Sys.println("passed class: " + read(new Answer()));
		Sys.println("passed literal: " + read({value: () -> 11}));
		Sys.println("passed override: " + read(new LateAnswer()));
		Sys.println("class adder: " + sum(new Answer(), 1, 2));
		Sys.println("literal adder: " + sum({add: (a:Int, b:Int) -> a * b}, 4, 5));

		final mixed:{var count:Int; function value():Int;} = new LateAnswer();
		Sys.println("mixed: " + mixed.count + " " + mixed.value());
		Sys.println("named override: " + named().value());
		final readers = new Array<{function value():Int;}>();
		readers.push(new Answer());
		readers.push({value: () -> 12});
		readers.push(new LateAnswer());
		var values = "";
		for (reader in readers)
			values += reader.value() + ";";
		Sys.println("array: " + values);
	}
}
