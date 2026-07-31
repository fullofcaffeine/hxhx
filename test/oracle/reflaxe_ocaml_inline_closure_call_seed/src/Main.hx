/**
	Freezes Haxe evaluation and result behavior for an immediately invoked
	closure.

	The same source runs through upstream Haxe 4.3.7 and reflaxe.ocaml. Its event
	log makes argument evaluation, closure execution, and value-versus-Void
	results observable without inspecting compiler internals.
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

	static function inlineValueCase():Void {
		reset();
		final offset = 1;
		final result = (function(value:Int):Int {
			record("inline");
			return offset + value;
		})(argument());
		printLine("inline_value result=" + result + " events=" + renderEvents());
	}

	static function inlineVoidCase():Void {
		reset();
		(function(value:Int):Void {
			record("inline_void");
			if (value != 41)
				record("bad_value");
		})(argument());
		printLine("inline_void events=" + renderEvents());
	}

	static function main():Void {
		inlineValueCase();
		inlineVoidCase();
	}
}
