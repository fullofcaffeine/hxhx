import haxe.CallStack;
import haxe.CallStack.StackItem;

/** Independent observation of native last-exception state across nested handlers. */
class Main {
	static function method(item:StackItem):String {
		return switch item {
			case FilePos(inner, _, _, _): inner == null ? "" : method(inner);
			case Method(owner, name): owner + "." + name;
			case _: "";
		};
	}

	static function contains(stack:Array<StackItem>, name:String):Bool {
		for (item in stack)
			if (method(item) == "Main." + name)
				return true;
		return false;
	}

	@:noInline static function origin():Void {
		throw "first";
	}

	@:noInline static function secondary():Void {
		throw "second";
	}

	@:noInline static function rethrowFirst():Void {
		try {
			origin();
		} catch (first:String) {
			final snapshot = haxe.NativeStackTrace.exceptionStack();
			final before = CallStack.toString(haxe.NativeStackTrace.toHaxe(snapshot));
			Sys.println("first-origin=" + contains(haxe.NativeStackTrace.toHaxe(snapshot), "origin"));
			try {
				secondary();
			} catch (_:String) {
				Sys.println("nested-secondary=" + contains(CallStack.exceptionStack(true), "secondary"));
			}
			Sys.println("snapshot-stable=" + (before == CallStack.toString(haxe.NativeStackTrace.toHaxe(snapshot))));
			Sys.println("after-nested-secondary=" + contains(CallStack.exceptionStack(true), "secondary"));
			throw first;
		}
	}

	static function main():Void {
		Sys.println("initial-empty=" + (CallStack.exceptionStack(true).length == 0));
		try {
			rethrowFirst();
		} catch (_:String) {
			final stack = CallStack.exceptionStack(true);
			Sys.println("rethrow-origin=" + contains(stack, "origin"));
			Sys.println("rethrow-secondary=" + contains(stack, "secondary"));
			Sys.println("rethrow-site=" + contains(stack, "rethrowFirst"));
		}
		Sys.println("after-catch-empty=" + (CallStack.exceptionStack(true).length == 0));
	}
}
