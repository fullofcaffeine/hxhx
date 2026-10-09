/** Disabled language traces discard operands; ordinary named calls still execute. */
class TraceDisabled {
	static var events:Int = 0;

	static function trace(value:Int):Void {
		events += value;
	}

	static function empty():Void {
		final trace = function():Void {
			events += 4;
		};
		trace();
	}

	static function main():Void {
		final trace = function(value:Int):Void {
			events += value;
		};
		trace({
			var discarded:Int = 10;
			events += discarded;
			throw "disabled operand executed";
			7;
		});
		trace(unknownIdentifier);
		trace({var invalid:Int = "not an Int"; invalid;});
		(trace)(2);
		TraceDisabled.trace(3);
		empty();
		if (events != 9)
			throw "ordinary trace-named calls changed";
	}
}
