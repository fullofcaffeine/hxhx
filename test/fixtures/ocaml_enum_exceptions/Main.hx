/** Two enum types share constructor spellings but must select different handlers. */
enum Failure {
	Empty;
	Problem(code:Int);
}

enum OtherFailure {
	Empty;
	Problem(code:Int);
}

/** Observe enum identity, handler order, rethrows, and control flow across native exceptions. */
class Main {
	static function produce():Failure {
		Sys.println("produce");
		return Failure.Problem(7);
	}

	static function caughtReturn():Int {
		try {
			throw Failure.Empty;
		} catch (caught:Failure) {
			return 11;
		}
		return -1;
	}

	static function main():Void {
		final value = produce();
		try {
			throw value;
		} catch (wrong:OtherFailure) {
			Sys.println("wrong enum");
		} catch (caught:Failure) {
			Sys.println(caught == value);
			switch caught {
				case Problem(code):
					Sys.println(code);
				case Empty:
					Sys.println("wrong constructor");
			}
		} catch (fallback:Dynamic) {
			Sys.println("wrong fallback");
		}
		Sys.println("after first catch");
		try {
			throw produce();
		} catch (caught:Failure) {
			Sys.println("second catch");
		}
		try {
			throw OtherFailure.Empty;
		} catch (wrong:Failure) {
			Sys.println("wrong singleton");
		} catch (caught:OtherFailure) {
			Sys.println(caught == OtherFailure.Empty);
		}
		try {
			try {
				throw value;
			} catch (wrong:OtherFailure) {
				Sys.println("wrong inner handler");
			}
		} catch (caught:Failure) {
			Sys.println(caught == value);
		}
		// Dynamic is the language's exception transport boundary under test.
		final dynamicValue:Dynamic = value;
		try {
			try {
				throw dynamicValue;
			} catch (transport:Dynamic) {
				Sys.println(transport == dynamicValue);
				throw transport;
			}
		} catch (caught:Failure) {
			Sys.println(caught == value);
			switch caught {
				case Problem(code):
					Sys.println(code);
				case Empty:
					Sys.println("lost payload");
			}
		}
		try {
			throw Failure.Empty;
		} catch (caught:Failure) {
			caught = Failure.Problem(9);
			switch caught {
				case Problem(code):
					Sys.println(code);
				case Empty:
					Sys.println("lost assignment");
			}
		}
		try {
			throw "text";
		} catch (wrong:Failure) {
			Sys.println("string matched enum");
		} catch (message:String) {
			Sys.println(message);
		}
		final missing:Failure = null;
		try {
			throw missing;
		} catch (wrong:Failure) {
			Sys.println("null matched enum");
		} catch (caught:Dynamic) {
			Sys.println(caught == null);
		}
		Sys.println(caughtReturn());
		var iteration = 0;
		while (iteration < 3) {
			iteration++;
			try {
				if (iteration == 1)
					continue;
				break;
			} catch (wrong:Failure) {
				Sys.println("control matched enum");
			} catch (wrong:Dynamic) {
				Sys.println("control matched Dynamic");
			}
		}
		Sys.println(iteration);
	}
}
