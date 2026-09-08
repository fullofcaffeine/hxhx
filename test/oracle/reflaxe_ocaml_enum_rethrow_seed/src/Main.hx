/** Ordinary enum values used to observe catch-and-rethrow behavior. */
enum Signal {
	Idle;
	Payload(value:Int);
	ArrayPayload(values:Array<Int>);
}

/** Compares typed enum rethrows with upstream Haxe 4.3.7. */
class Main {
	static var retained:Signal = Signal.Idle;
	static var retainedDynamic:Dynamic;
	static var evaluations:Int = 0;

	/** Preserve the selected catch value through another exception boundary. */
	static function relay(action:() -> Void):Void {
		try {
			action();
		} catch (error:Signal) {
			retained = error;
			throw error;
		} catch (error:haxe.io.Error) {
			throw error;
		} catch (error:String) {
			throw error;
		} catch (error:haxe.Exception) {
			throw error;
		}
	}

	static function failIdle():Void {
		throw Signal.Idle;
	}

	static function failPayload():Void {
		evaluations += 1;
		throw Signal.Payload(7);
	}

	static function failIo():Void {
		throw haxe.io.Error.Blocked;
	}

	/** Rethrows one enum with a caller-owned mutable payload. */
	static function relayArray(values:Array<Int>):Void {
		try {
			throw Signal.ArrayPayload(values);
		} catch (error:Signal) {
			retained = error;
			throw error;
		}
	}

	/** Routes the same enum through a Dynamic catch before a typed catch. */
	static function relayArrayDynamic(values:Array<Int>):Void {
		try {
			throw Signal.ArrayPayload(values);
		} catch (error:Dynamic) {
			throw error;
		}
	}

	/** Preserves an observable Dynamic enum box through one typed catch. */
	static function relayDynamicInput(values:Array<Int>):Void {
		final value:Dynamic = Signal.ArrayPayload(values);
		retainedDynamic = value;
		try {
			throw value;
		} catch (error:Signal) {
			throw error;
		}
	}

	/** Proves that same-named nested catch bindings keep distinct origins. */
	static function relayNested():Void {
		try {
			try {
				throw Signal.Idle;
			} catch (error:Signal) {
				throw error;
			}
		} catch (error:Signal) {
			throw error;
		}
	}

	static function main():Void {
		try {
			relay(failIdle);
		} catch (error:Signal) {
			Sys.println(error == Signal.Idle && error == retained ? "idle:identity" : "wrong");
		}
		evaluations = 0;
		try {
			relay(failPayload);
		} catch (error:Signal) {
			switch (error) {
				case Payload(value):
					Sys.println("payload:" + value + (error == retained ? ":identity" : ":wrong-identity"));
				case Idle, ArrayPayload(_):
					Sys.println("wrong");
			}
		}
		Sys.println("evaluations:" + evaluations);
		try {
			relay(failIo);
		} catch (error:haxe.io.Error) {
			Sys.println(error == haxe.io.Error.Blocked ? "io" : "wrong");
		}

		final values = [3];
		final other = [3];
		try {
			relayArray(values);
		} catch (error:Signal) {
			switch (error) {
				case ArrayPayload(received):
					received[0] = 9;
					Sys.println(error == retained && received == values && received != other ? "token:identity" : "wrong-token");
				case Idle, Payload(_):
					Sys.println("wrong");
			}
		}
		Sys.println("token-value:" + values[0]);

		try {
			relayArrayDynamic(values);
		} catch (error:Signal) {
			switch (error) {
				case ArrayPayload(received):
					Sys.println(received == values ? "dynamic-to-typed:identity" : "wrong-dynamic-to-typed");
				case Idle, Payload(_):
					Sys.println("wrong");
			}
		}

		try {
			relayDynamicInput(values);
		} catch (error:Dynamic) {
			Sys.println(error == retainedDynamic ? "typed-to-dynamic:identity" : "wrong-typed-to-dynamic");
		}

		try {
			relayNested();
		} catch (error:Signal) {
			Sys.println(error == Signal.Idle ? "nested:identity" : "wrong-nested");
		}
	}
}
