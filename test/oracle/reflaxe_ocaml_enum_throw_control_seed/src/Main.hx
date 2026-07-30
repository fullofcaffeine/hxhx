/** Values used to observe exact enum transport through Haxe exceptions. */
enum Signal {
	Idle;
	Payload(value:Int);
	Pair(label:String, value:Int);
}

/** Freezes upstream Haxe 4.3.7 behavior for direct enum constructor throws. */
class Main {
	static var evaluations:Int = 0;

	static function line(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	/** Returns a payload while making repeated evaluation observable. */
	static function nextValue(value:Int):Int {
		evaluations += 1;
		return value;
	}

	static function throwIdle():Void {
		throw Signal.Idle;
	}

	static function throwPayload(value:Int):Void {
		throw Signal.Payload(nextValue(value));
	}

	static function throwPair(label:String, value:Int):Void {
		throw Signal.Pair(label, nextValue(value));
	}

	static function idleCase():Void {
		try {
			throwIdle();
		} catch (caught:Signal) {
			switch (caught) {
				case Idle:
					line("idle");
				case Payload(value):
					line("wrong-idle-payload:" + value);
				case Pair(label, value):
					line("wrong-idle-pair:" + label + ":" + value);
			}
		} catch (_:Dynamic) {
			line("wrong-idle-dynamic");
		}
	}

	static function payloadCase():Void {
		evaluations = 0;
		try {
			throwPayload(7);
		} catch (caught:Signal) {
			switch (caught) {
				case Payload(value):
					line("payload:" + value);
				case Idle:
					line("wrong-payload-idle");
				case Pair(label, value):
					line("wrong-payload-pair:" + label + ":" + value);
			}
		} catch (_:Dynamic) {
			line("wrong-payload-dynamic");
		}
		line("evaluations:" + evaluations);
	}

	static function acrossCallCase():Void {
		try {
			throwPayload(11);
		} catch (caught:Signal) {
			switch (caught) {
				case Payload(value):
					line("across:" + value);
				case Idle:
					line("wrong-across-idle");
				case Pair(label, value):
					line("wrong-across-pair:" + label + ":" + value);
			}
		} catch (_:Dynamic) {
			line("wrong-across-dynamic");
		}
	}

	static function pairCase():Void {
		evaluations = 0;
		try {
			throwPair("x", 13);
		} catch (caught:Signal) {
			switch (caught) {
				case Pair(label, value):
					line("pair:" + label + ":" + value);
				case Idle:
					line("wrong-pair-idle");
				case Payload(value):
					line("wrong-pair-payload:" + value);
			}
		} catch (_:Dynamic) {
			line("wrong-pair-dynamic");
		}
		line("pair-evaluations:" + evaluations);
	}

	static function dynamicCase():Void {
		evaluations = 0;
		try {
			throwPair("y", 17);
		} catch (_:Int) {
			line("wrong-dynamic-int");
		} catch (_:Dynamic) {
			line("dynamic");
		}
		line("dynamic-evaluations:" + evaluations);
	}

	static function main():Void {
		idleCase();
		payloadCase();
		acrossCallCase();
		pairCase();
		dynamicCase();
	}
}
