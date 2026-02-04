import haxe.Exception;
import haxe.ValueException;

class Main {
	static function main() {
		try {
			throw 123;
		} catch (e:Int) {
			Sys.println("catch_int=" + e);
		}

		try {
			throw 123;
		} catch (e:ValueException) {
			Sys.println("catch_value=" + Std.string(e.value));
			Sys.println("catch_value_message=" + e.message);
		}

		try {
			throw 123;
		} catch (e:Exception) {
			Sys.println("catch_exception_message=" + e.message);
		}

		try {
			throw "x";
		} catch (e:Exception) {
			Sys.println("catch_exception_string=" + e.message);
		}

		final thrown = new MyExn("boom");
		try {
			try {
				throw thrown;
			} catch (e:ValueException) {
				Sys.println("unexpected_valueexception_for_myexn");
			} catch (e:Exception) {
				Sys.println("caught_exception_for_myexn=" + (e == thrown));
				throw e;
			}
		} catch (e:MyExn) {
			Sys.println("rethrown_myexn=" + (e == thrown));
		}
	}
}

class MyExn extends Exception {
	public function new(msg:String) {
		super(msg);
	}
}

