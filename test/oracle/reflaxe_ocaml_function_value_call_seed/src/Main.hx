/**
	Freezes Haxe evaluation order for calling an already-created function value.

	The same source runs through upstream Haxe 4.3.7 and reflaxe.ocaml. Its event
	log makes callee selection, argument evaluation, callback execution, and
	failure short-circuiting observable without inspecting compiler internals.
**/
class Main {
	static var events:Array<String> = [];

	static function record(event:String):Void {
		events.push(event);
	}

	static function reset():Void {
		events = [];
	}

	static function renderEvents():String {
		return events.join(",");
	}

	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function argument():Int {
		record("argument");
		return 41;
	}

	static function increment(value:Int):Int {
		record("method");
		return value + 1;
	}

	static function closureResult(value:Int, offset:Int):Int {
		record("closure");
		return value + offset;
	}

	static function base(value:Int):Int {
		record("base");
		return value;
	}

	static function shifted(value:Int):Int {
		record("shifted");
		return value + 1;
	}

	static function select(useShifted:Bool):Int->Int {
		record("selector");
		return useShifted ? shifted : base;
	}

	static function selectOrFail(fail:Bool):Int->Int {
		record("failing_callee");
		if (fail)
			throw "callee failed";
		return shifted;
	}

	static function closureCase():Void {
		reset();
		final offset = 1;
		final callback:Int->Int = value -> closureResult(value, offset);
		final result = callback(argument());
		printLine("closure result=" + result + " events=" + renderEvents());
	}

	static function methodValueCase():Void {
		reset();
		final callback:Int->Int = increment;
		final result = callback(argument());
		printLine("method_value result=" + result + " events=" + renderEvents());
	}

	static function selectedCalleeCase():Void {
		reset();
		final result = select(true)(argument());
		printLine("selected_callee result=" + result + " events=" + renderEvents());
	}

	static function failedCalleeCase():Void {
		reset();
		final ignored = try {
			selectOrFail(true)(argument());
		} catch (_:Dynamic) {
			record("caught");
			-1;
		}
		if (ignored != -1)
			record("unexpected_result");
		printLine("failed_callee events=" + renderEvents());
	}

	static function main():Void {
		closureCase();
		methodValueCase();
		selectedCalleeCase();
		failedCalleeCase();
	}
}
