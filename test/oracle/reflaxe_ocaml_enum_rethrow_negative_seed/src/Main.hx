/** Enum used to keep unsupported catch-local flows outside the first proof. */
enum Signal {
	Idle;
	Payload(value:Int);
}

/** Exercises catch bindings that must not receive direct-rethrow authority. */
class Main {
	static function fail():Void {
		throw Signal.Idle;
	}

	static function relay():Void {
		try {
			fail();
		} catch (error:Signal) {
			#if enum_rethrow_mutation
			error = Signal.Payload(9);
			throw error;
			#elseif enum_rethrow_capture
			final read = () -> error;
			read();
			throw error;
			#elseif enum_rethrow_alias
			final alias = error;
			throw alias;
			#elseif enum_rethrow_cast
			throw(cast error : Signal);
			#else
			throw error;
			#end
		}
	}

	static function main():Void {
		try {
			relay();
		} catch (_:Signal) {
			Sys.println("caught");
		}
	}
}
