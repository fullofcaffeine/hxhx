/**
	Freezes optional String behavior for an already-created function value.

	The event log distinguishes supplied source evaluation from omission, which
	has no source expression, and makes callback execution order observable.
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

	static function required():String {
		record("required");
		return "Ada";
	}

	static function suffix():String {
		record("suffix");
		return "!";
	}

	static function explicitNull():String {
		record("explicit_null");
		return null;
	}

	static function greet(name:String, ?suffix:String):String {
		record("greet");
		return suffix == null ? "hi " + name : "hi " + name + suffix;
	}

	static function only(?value:String):String {
		record("only");
		return value == null ? "none" : value;
	}

	static function requiredOmittedCase():Void {
		reset();
		final callback = greet;
		final result = callback(required());
		printLine("required_omitted result=" + result + " events=" + renderEvents());
	}

	static function requiredSuppliedCase():Void {
		reset();
		final callback = greet;
		final result = callback(required(), suffix());
		printLine("required_supplied result=" + result + " events=" + renderEvents());
	}

	static function requiredNullCase():Void {
		reset();
		final callback = greet;
		final result = callback(required(), explicitNull());
		printLine("required_null result=" + result + " events=" + renderEvents());
	}

	static function requiredLiteralNullCase():Void {
		reset();
		final callback = greet;
		final result = callback(required(), null);
		printLine("required_literal_null result=" + result + " events=" + renderEvents());
	}

	static function onlyOmittedCase():Void {
		reset();
		final callback = only;
		final result = callback();
		printLine("only_omitted result=" + result + " events=" + renderEvents());
	}

	static function onlySuppliedCase():Void {
		reset();
		final callback = only;
		final result = callback(suffix());
		printLine("only_supplied result=" + result + " events=" + renderEvents());
	}

	static function onlyNullCase():Void {
		reset();
		final callback = only;
		final result = callback(explicitNull());
		printLine("only_null result=" + result + " events=" + renderEvents());
	}

	static function onlyLiteralNullCase():Void {
		reset();
		final callback = only;
		final result = callback(null);
		printLine("only_literal_null result=" + result + " events=" + renderEvents());
	}

	static function main():Void {
		requiredOmittedCase();
		requiredSuppliedCase();
		requiredNullCase();
		requiredLiteralNullCase();
		onlyOmittedCase();
		onlySuppliedCase();
		onlyNullCase();
		onlyLiteralNullCase();
	}
}
