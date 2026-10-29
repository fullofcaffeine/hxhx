import backend.source.PhpRenderCallback.withPhpPreferredEnum;

/** Observe the actual extracted helper without importing the whole compiler emitter. */
class PhpRenderCallbackFixture {
	static function main():Void {
		var calls = 0;
		Sys.println(withPhpPreferredEnum("Outer", () -> {
			calls++;
			return withPhpPreferredEnum("Inner", () -> {
				calls++;
				return "rendered";
			});
		}));
		Sys.println(calls);
		Sys.println(withPhpPreferredEnum(null, () -> "").length);
		Sys.println(withPhpPreferredEnum(null, () -> 7) + 1);
		Sys.println(withPhpPreferredEnum("Flag", () -> true));
		final values = [3, 4];
		final returned = withPhpPreferredEnum("Array", () -> values);
		if (returned != values)
			throw "callback result lost array identity";
		returned.push(5);
		Sys.println(values.join(","));
		final record = {value: 6};
		final returnedRecord = withPhpPreferredEnum("Record", () -> record);
		if (returnedRecord != record)
			throw "callback result lost record identity";
		returnedRecord.value = 9;
		Sys.println(record.value);
		var caught = false;
		try {
			withPhpPreferredEnum("Failure", () -> {
				calls++;
				throw "callback-failure";
				return "unreachable";
			});
		} catch (message:String) {
			if (message != "callback-failure")
				throw message;
			caught = true;
		}
		if (!caught || calls != 3)
			throw "callback failure was swallowed or invoked more than once";
		Sys.println("exception-preserved");
	}
}
