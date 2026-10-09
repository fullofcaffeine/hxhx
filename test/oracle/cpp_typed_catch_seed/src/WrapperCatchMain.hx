/**
	Observe wrapper selection, identity, and conversion timing through public exception APIs.
	Dynamic is confined to throw/catch probes whose purpose is to preserve arbitrary payloads before narrowing.
**/
class WrapperCatchMain {
	static function payloadFirst(value:Dynamic):String {
		try {
			throw value;
		} catch (_:CountingPayload) {
			return "payload";
		} catch (_:haxe.ValueException) {
			return "wrapper";
		} catch (_:haxe.Exception) {
			return "exception";
		} catch (_:Dynamic) {
			return "dynamic";
		}
	}

	static function wrapperFirst(value:Dynamic):String {
		try {
			throw value;
		} catch (_:haxe.ValueException) {
			return "wrapper";
		} catch (_:CountingPayload) {
			return "payload";
		} catch (_:haxe.Exception) {
			return "exception";
		} catch (_:Dynamic) {
			return "dynamic";
		}
	}

	static function exceptionFirst(value:Dynamic):String {
		try {
			throw value;
		} catch (_:haxe.Exception) {
			return "exception";
		} catch (_:CountingPayload) {
			return "payload";
		} catch (_:Dynamic) {
			return "dynamic";
		}
	}

	static function dynamicCatch(value:Dynamic):Dynamic {
		try {
			throw value;
		} catch (caught:Dynamic) {
			return caught;
		}
	}

	static function main():Void {
		final payload = new CountingPayload();
		final previous = new haxe.Exception("previous");
		Sys.println("explicit-before=" + payload.conversions);
		final wrapper = new haxe.ValueException(payload, previous);
		Sys.println("explicit-after=" + payload.conversions);
		Sys.println("explicit-value=" + (wrapper.value == payload));
		Sys.println("explicit-previous=" + (wrapper.previous == previous));
		Sys.println("explicit-payload-first=" + payloadFirst(wrapper));
		Sys.println("explicit-wrapper-first=" + wrapperFirst(wrapper));
		Sys.println("explicit-exception-first=" + exceptionFirst(wrapper));
		Sys.println("explicit-dynamic-payload=" + (dynamicCatch(wrapper) == payload));
		Sys.println("explicit-dynamic-wrapper=" + (dynamicCatch(wrapper) == wrapper));
		try {
			try {
				throw wrapper;
			} catch (caught) {
				Sys.println("explicit-default-identity=" + (caught == wrapper));
				Sys.println("explicit-default-previous=" + (caught.previous == previous));
				Sys.println("explicit-native-stable=" + (caught.native == wrapper.native));
				throw caught;
			}
		} catch (again) {
			Sys.println("explicit-rethrow-identity=" + (again == wrapper));
			Sys.println("explicit-rethrow-previous=" + (again.previous == previous));
			Sys.println("explicit-rethrow-message=" + again.message);
		}
		Sys.println("explicit-final-conversions=" + payload.conversions);

		final direct = new CountingPayload();
		try {
			throw direct;
		} catch (caught:CountingPayload) {
			Sys.println("direct-identity=" + (caught == direct));
			Sys.println("direct-conversions=" + direct.conversions);
		}
		Sys.println("ordinary-payload-first=" + payloadFirst(direct));
		Sys.println("ordinary-wrapper-first=" + wrapperFirst(direct));
		Sys.println("ordinary-exception-first=" + exceptionFirst(direct));
		Sys.println("ordinary-dynamic-identity=" + (dynamicCatch(direct) == direct));
		final implicit = new CountingPayload();
		try {
			try {
				throw implicit;
			} catch (caught) {
				Sys.println("implicit-wrapper=" + Std.isOfType(caught, haxe.ValueException));
				Sys.println("implicit-message=" + caught.message);
				Sys.println("implicit-conversions=" + implicit.conversions);
				throw caught;
			}
		} catch (again:CountingPayload) {
			Sys.println("implicit-rethrow-payload=" + (again == implicit));
		} catch (_:Dynamic) {
			Sys.println("implicit-rethrow-payload=false");
		}
		Sys.println("implicit-final-conversions=" + implicit.conversions);

		final exception = new haxe.Exception("actual", previous);
		final originalStack = haxe.CallStack.toString(exception.stack);
		Sys.println("actual-dynamic-identity=" + (dynamicCatch(exception) == exception));
		try {
			try {
				throw exception;
			} catch (caught) {
				throw caught;
			}
		} catch (again) {
			Sys.println("actual-rethrow-identity=" + (again == exception));
			Sys.println("actual-rethrow-previous=" + (again.previous == previous));
			Sys.println("actual-native-stable=" + (again.native == exception.native));
			Sys.println("actual-stack-present=" + (again.stack.length > 0));
			Sys.println("actual-stack-stable=" + (haxe.CallStack.toString(again.stack) == originalStack));
		}
		try {
			throw null;
		} catch (caught) {
			final nullable = Std.downcast(caught, haxe.ValueException);
			Sys.println("null-wrapper=" + (nullable != null));
			Sys.println("null-payload=" + (nullable != null && nullable.value == null));
		}

		final failing = new CountingPayload(true);
		try {
			try {
				throw failing;
			} catch (caught) {
				Sys.println("conversion-handler-entered=" + caught.message);
			}
		} catch (failure:String) {
			Sys.println("conversion-threw=" + failure);
		}
		Sys.println("conversion-attempts=" + failing.conversions);
		try {
			try {
				throw "original";
			} catch (value:String) {
				value = "replacement";
				throw value;
			}
		} catch (value:String) {
			Sys.println("reassigned-rethrow=" + value);
		}
	}
}

/** A payload with observable conversion detects eager wrapping and repeated message construction. */
class CountingPayload {
	public var conversions:Int = 0;

	final failConversion:Bool;

	public function new(failConversion:Bool = false)
		this.failConversion = failConversion;

	public function toString():String {
		conversions++;
		if (failConversion)
			throw "conversion-failed";
		return "payload-text";
	}
}
