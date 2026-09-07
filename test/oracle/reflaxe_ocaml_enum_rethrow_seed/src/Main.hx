/** Ordinary enum values used to observe catch-and-rethrow behavior. */
enum Signal {
	Idle;
	Payload(value:Int);
}

/** Compares typed enum rethrows with upstream Haxe 4.3.7. */
class Main {
	/** Preserve the selected catch value through another exception boundary. */
	static function relay(action:() -> Void):Void {
		try {
			action();
		} catch (error:Signal) {
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
		throw Signal.Payload(7);
	}

	static function failIo():Void {
		throw haxe.io.Error.Blocked;
	}

	static function main():Void {
		try {
			relay(failIdle);
		} catch (error:Signal) {
			Sys.println(error == Signal.Idle ? "idle" : "wrong");
		}
		try {
			relay(failPayload);
		} catch (error:Signal) {
			switch (error) {
				case Payload(value):
					Sys.println("payload:" + value);
				case Idle:
					Sys.println("wrong");
			}
		}
		try {
			relay(failIo);
		} catch (error:haxe.io.Error) {
			Sys.println(error == haxe.io.Error.Blocked ? "io" : "wrong");
		}
	}
}
