/** Observe authored exception providers and deterministic stack operations. */
class Main {
	static function main():Void {
		final base = new haxe.Exception("base");
		Sys.println(base.message);
		Sys.println(base.previous == null);
		final value = new haxe.ValueException("payload", base);
		Sys.println(value.message);
		Sys.println(value.value);
		Sys.println(value.previous == base);
		Sys.println(Std.isOfType(value, haxe.Exception));
		try {
			throw value;
		} catch (caught:haxe.Exception) {
			Sys.println(caught == value);
		}
		Sys.println(base.stack.length >= 0);
		Sys.println(haxe.CallStack.toString([haxe.CallStack.StackItem.Module("probe")]) == "\nCalled from module probe");
		var stack:haxe.CallStack = [haxe.CallStack.StackItem.Module("a"), haxe.CallStack.StackItem.Module("b")];
		Sys.println(stack.length);
		Sys.println(stack.subtract([haxe.CallStack.StackItem.Module("b")]).length);
	}
}
