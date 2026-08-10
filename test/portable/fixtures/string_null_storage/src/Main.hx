class StringState {
	public var omitted:String;
	public var empty:String = "";
	public var explicitNull:String = null;

	public function new() {}
}

class Main {
	static var omitted:String;
	static var empty:String = "";
	static var explicitNull:String = null;

	static function echo(value:String):String {
		return value;
	}

	static function classify(value:String):String {
		return value == null ? "null" : value == "" ? "empty" : value;
	}

	static function makeStringCallback():Int->String {
		return value -> 'value=$value';
	}

	static function main():Void {
		final state = new StringState();
		var local:String;
		local = "local";
		var readableBeforeWrite:String = null;
		final localDefault = classify(readableBeforeWrite);
		readableBeforeWrite = "after";
		final beforeWrites = [
			classify(state.omitted),
			classify(state.empty),
			classify(state.explicitNull),
			classify(omitted),
			classify(empty),
			classify(explicitNull),
			classify(echo(omitted)),
			local,
			localDefault,
			readableBeforeWrite,
			makeStringCallback()(1)
		];
		state.omitted = "instance-written";
		final result = beforeWrites.concat([classify(state.omitted)]).join("|");
		#if js
		js.Syntax.code("console.log({0})", result);
		#else
		Sys.println(result);
		#end
	}
}
