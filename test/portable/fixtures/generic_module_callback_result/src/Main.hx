/** Consumes generic module callback results through concrete typed operations. */
class Main {
	static var calls:Int = 0;

	static function text():String {
		calls++;
		return "value";
	}

	static function main():Void {
		final label:String = Bridge.isolate(false, () -> text());
		Sys.println(label.toUpperCase());
		final number:Int = Bridge.isolate(true, () -> 40);
		Sys.println(number + 2);
		final flag:Bool = Bridge.isolate(false, () -> true);
		Sys.println(flag ? "yes" : "no");
		final original = new Box(3);
		final result:Box = Bridge.isolate(false, () -> original);
		result.value += 4;
		Sys.println(result == original);
		Sys.println(original.value);
		Sys.println(calls);
		try {
			final unused:String = Bridge.isolate(false, () -> {
				throw new haxe.Exception("expected");
				return "unreachable";
			});
			Sys.println(unused);
		} catch (error:haxe.Exception) {
			Sys.println(error.message);
		}
		checkCarriers();
		checkRestoration();
	}

	/** Uses the forwarded value without changing its container or callback identity. */
	static function checkCarriers():Void {
		final stored:Void->String = () -> "stored";
		Sys.println(Bridge.isolate(false, stored));
		Sys.println(Bridge.isolate(true, () -> false) ? "wrong" : "false-preserved");
		final absent:Null<Int> = null;
		final empty:Null<Int> = Bridge.isolate(false, () -> absent);
		if (empty != null)
			throw "nullable Int lost null";
		final present:Null<Int> = 23;
		final number:Null<Int> = Bridge.isolate(true, () -> present);
		if (number == null || number != 23)
			throw "nullable Int lost value";
		final nullableFlag:Null<Bool> = false;
		final returnedFlag:Null<Bool> = Bridge.isolate(false, () -> nullableFlag);
		if (returnedFlag == null || returnedFlag != false)
			throw "nullable Bool lost false";
		Sys.println("nullable-preserved");
		final values = ["first"];
		final returned = Bridge.isolate(false, () -> values);
		if (returned != values)
			throw "array identity changed";
		returned.push("second");
		Sys.println(values.join(","));
		final record = {value: 4};
		final returnedRecord = Bridge.isolate(true, () -> record);
		if (returnedRecord != record)
			throw "record identity changed";
		returnedRecord.value = 9;
		Sys.println(record.value);
		final maps = Bridge.isolate(false, () -> {
			final arguments = new haxe.ds.StringMap<String>();
			arguments.set("key", "argument");
			final locals = new haxe.ds.StringMap<String>();
			locals.set("key", "local");
			return {arguments: arguments, locals: locals};
		});
		Sys.println(maps.arguments.get("key") + ":" + maps.locals.get("key"));
		final callback = Bridge.isolate(false, () -> stored);
		if (callback != stored)
			throw "returned callback identity changed";
		Sys.println(callback());
		var count = 0;
		final effect:Void->Void = () -> count++;
		Bridge.isolate(false, effect);
		Sys.println(count);
	}

	/** Matches the compiler's save, invoke, restore, and rethrow control pattern. */
	static function checkRestoration():Void {
		final state = new Box(5);
		final value = Bridge.restored(state, () -> {
			state.value = 99;
			return "restored";
		});
		Sys.println(value + ":" + state.value);
		try {
			Bridge.restored(state, () -> {
				state.value = 100;
				throw new haxe.Exception("restore-error");
				return "unreachable";
			});
		} catch (error:haxe.Exception) {
			Sys.println(error.message + ":" + state.value);
		}
		Sys.println(Bridge.restored(null, () -> "direct"));
	}
}
