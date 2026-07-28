class Main {
	static var events:String = "";
	static var pushed:Array<Int> = [];

	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function mark(value:String):Void {
		if (events.length > 0)
			events += ",";
		events += value;
	}

	static function capture(label:String, action:() -> Void):Void {
		events = "";
		action();
		printLine(label + "=" + events);
	}

	static function branch(stop:Bool):Void {
		mark("before");
		if (stop)
			return;
		mark("after");
	}

	static function loop(stopAt:Int):Void {
		var index = 0;
		while (index < 4) {
			mark("loop" + index);
			if (index == stopAt)
				return;
			index++;
		}
		mark("after");
	}

	static function throughTry(stop:Bool):Void {
		try {
			mark("try");
			if (stop)
				return;
			mark("try-after");
		} catch (_:Dynamic) {
			mark("caught");
		}
		mark("done");
	}

	static function fromCatch(stop:Bool):Void {
		try {
			throw 41;
		} catch (_:Int) {
			mark("catch");
			if (stop)
				return;
			mark("catch-after");
		} catch (_:Dynamic) {
			mark("wrong");
		}
		mark("done");
	}

	/**
		Leaves a value-producing target operation at the end of a Void function.

		Haxe discards Array.push's Int result. The early return forces the target
		to join that normal path with its private payloadless return signal.
	**/
	static function pushAfterGuard(stop:Bool):Void {
		if (stop)
			return;
		pushed.push(7);
	}

	static function nestedClosure():Void {
		final local = function(stop:Bool):Void {
			mark("inner");
			if (stop)
				return;
			mark("inner-after");
		};
		local(true);
		mark("outer");
	}

	static function main() {
		capture("branchStop", () -> branch(true));
		capture("branchRun", () -> branch(false));
		capture("loop2", () -> loop(2));
		capture("tryStop", () -> throughTry(true));
		capture("tryRun", () -> throughTry(false));
		capture("catchStop", () -> fromCatch(true));
		capture("catchRun", () -> fromCatch(false));
		pushed = [];
		pushAfterGuard(false);
		pushAfterGuard(true);
		printLine("pushAfterGuard=" + pushed.length);
		capture("closure", nestedClosure);
		printLine("OK void_return_control");
	}
}
