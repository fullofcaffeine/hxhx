class Main {
	static function acceptsFunction<T:haxe.Constraints.Function>(value:T):Bool {
		return value != null;
	}

	static function main() {
		Sys.println("constraints.fn=" + acceptsFunction(() -> 1));

		final values:haxe.DynamicAccess<Int> = new haxe.DynamicAccess<Int>();
		values["a"] = 10;
		values["b"] = 32;
		Sys.println("dyn.sum=" + (values["a"] + values["b"]));
		values.remove("a");
		Sys.println("dyn.hasA=" + values.exists("a"));

		final callStack:haxe.CallStack = [];
		Sys.println("stack.nonneg=" + (callStack.length >= 0));

		final entryPointClass = Type.getClassName(haxe.EntryPoint);
		Sys.println("entry.class=" + (entryPointClass != null));

		var flags = new haxe.EnumFlags<BucketState>();
		flags.set(Ready);
		flags.setTo(Busy, true);
		flags.unset(Busy);
		Sys.println("flags.ready=" + flags.has(Ready));
		Sys.println("flags.busy=" + flags.has(Busy));
		Sys.println("enum.name=" + haxe.EnumTools.getName(BucketState));
		Sys.println("enum.ctors=" + haxe.EnumTools.getConstructors(BucketState).join(","));
		final created = haxe.EnumTools.createByName(BucketState, "Done", [7]);
		final createdDone = switch (created) {
			case Done(code):
				code == 7;
			case _:
				false;
		};
		Sys.println("enum.createdDone=" + createdDone);

		final baseException = new haxe.Exception("bucket");
		Sys.println("ex.message=" + baseException.message);
		Sys.println("ex.prev=" + (baseException.previous == null));
		try {
			throw "wrapped";
		} catch (caught:haxe.Exception) {
			Sys.println("ex.caught=" + caught.message);
		}

		final http = new haxe.Http("http://example.invalid/path");
		http.setHeader("X-Test", "1");
		http.setParameter("q", "hxhx");
		Sys.println("http.url=" + http.url);

		final int64Value = haxe.Int64.ofInt(41);
		final int64Delta = haxe.Int64Helper.parseString("1");
		final int64Sum = haxe.Int64.add(int64Value, int64Delta);
		Sys.println("int64.eq42=" + (haxe.Int64.compare(int64Sum, haxe.Int64.ofInt(42)) == 0));

		final jsonParsed = haxe.Json.parse("{\"value\":7}");
		final jsonValue:Int = cast Reflect.field(jsonParsed, "value");
		Sys.println("json.value=" + jsonValue);

		final formatted = haxe.Log.formatOutput("hello", {
			fileName: "Main.hx",
			lineNumber: 12,
			className: "Main",
			methodName: "main"
		});
		Sys.println("log.formatted=" + formatted);
	}
}
