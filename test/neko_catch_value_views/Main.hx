interface Marker {}

class Payload implements Marker {
	public var stringCalls = 0;

	public function new() {}

	public function toString():String {
		stringCalls++;
		return "payload-string";
	}
}

class ChildError extends haxe.Exception {}
class OtherError extends haxe.Exception {}

/** Black-box observer for the two values visible at Neko catch dispatch. */
class Main {
	static function main():Void {
		try {
			throw true;
		} catch (_:Int) {
			Sys.println("wrong-bool-int");
		} catch (value:Bool) {
			Sys.println("bool:" + value);
		}
		final array = [1, 2];
		try {
			throw new haxe.ValueException(array);
		} catch (value:Array<Dynamic>) {
			// The generic carrier is inspected only for identity at this boundary.
			Sys.println("array-payload:" + (value == array));
		}
		final textWrapper = new haxe.ValueException("payload");
		try {
			throw textWrapper;
		} catch (value:haxe.Exception) {
			Sys.println("base-first-identity:" + (value == textWrapper));
		} catch (_:String) {
			Sys.println("wrong-later-string");
		}
		try {
			throw textWrapper;
		} catch (value:String) {
			Sys.println("string-payload:" + value);
		} catch (_:Dynamic) {
			Sys.println("wrong-string-fallback");
		}

		final payload = new Payload();
		try {
			throw payload;
		} catch (value:Payload) {
			Sys.println("class-carrier:" + (value == payload));
		}
		final objectWrapper = new haxe.ValueException(payload);
		try {
			throw objectWrapper;
		} catch (value:Marker) {
			Sys.println("interface-payload-identity:" + (value == payload));
		} catch (_:Dynamic) {
			Sys.println("wrong-interface-fallback");
		}

		try {
			throw textWrapper;
		} catch (value:Dynamic) {
			Sys.println("dynamic-carrier-identity:" + (value == textWrapper));
		}
		try {
			try {
				throw textWrapper;
			} catch (_:OtherError) {
				Sys.println("wrong-inner-catch");
			}
		} catch (value:Dynamic) {
			Sys.println("unmatched-carrier-identity:" + (value == textWrapper));
		}
		final expression = try {
			throw textWrapper;
			"unreachable";
		} catch (_:Int) {
			"wrong-integer";
		} catch (value:String) {
			value;
		} catch (_:haxe.Exception) {
			"wrong-base-exception";
		};
		Sys.println("expression-payload:" + expression);

		final directPayload = new Payload();
		try {
			throw directPayload;
		} catch (_:Marker) {
			Sys.println("ordinary-before-conversion:" + directPayload.stringCalls);
		} catch (_:haxe.Exception) {
			Sys.println("wrong-exception-order");
		}

		final unmatchedPayload = new Payload();
		try {
			throw unmatchedPayload;
		} catch (_:ChildError) {
			Sys.println("wrong-child");
		} catch (_:OtherError) {
			Sys.println("wrong-other");
		} catch (value:Dynamic) {
			Sys.println("subclass-conversions-before-dynamic:" + unmatchedPayload.stringCalls + ":" + Std.isOfType(value, Payload));
		}

		final child = new ChildError("child");
		try {
			throw child;
		} catch (_:OtherError) {
			Sys.println("wrong-other-subclass");
		} catch (value:ChildError) {
			Sys.println("subclass-carrier-identity:" + (value == child));
		}
		try {
			throw new haxe.ValueException(child);
		} catch (value:ChildError) {
			Sys.println("exception-subclass-payload-identity:" + (value == child));
		} catch (_:Dynamic) {
			Sys.println("wrapped-subclass-remains-carrier");
		}

		final convertedPayload = new Payload();
		try {
			throw convertedPayload;
		} catch (error:haxe.Exception) {
			Sys.println("base-exception-conversion:" + convertedPayload.stringCalls + ":" + error.message);
		}
	}
}
