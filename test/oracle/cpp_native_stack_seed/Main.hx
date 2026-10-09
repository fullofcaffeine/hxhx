import haxe.CallStack;
import haxe.CallStack.StackItem;

/** Observe stack availability separately from snapshot, skip, and rethrow behavior. */
class Main {
	/** Keep a named caller in builds that record Haxe stack frames. */
	@:noInline
	static function capture():Array<StackItem> {
		return CallStack.callStack();
	}

	/** A captured native snapshot must support repeatable conversion and exact prefix skipping. */
	@:noInline
	static function checkNativeSnapshot():Void {
		final snapshot = haxe.NativeStackTrace.callStack();
		final full = haxe.NativeStackTrace.toHaxe(snapshot);
		final again = haxe.NativeStackTrace.toHaxe(snapshot);
		final skipped = haxe.NativeStackTrace.toHaxe(snapshot, 1);
		Sys.println("snapshot-present=" + (full.length > 0));
		Sys.println("snapshot-stable=" + (CallStack.toString(full) == CallStack.toString(again)));
		Sys.println("skip-one=" + (CallStack.toString(skipped) == CallStack.toString(full.slice(1))));
		Sys.println("skip-all=" + (haxe.NativeStackTrace.toHaxe(snapshot, full.length).length == 0));
	}

	/** Construct at a separate call site so later throws cannot replace the origin snapshot. */
	@:noInline
	static function construct():haxe.Exception {
		return new haxe.Exception("origin");
	}

	static function main():Void {
		Sys.println("call-present=" + (capture().length > 0));
		checkNativeSnapshot();
		final original = construct();
		final before = CallStack.toString(original.stack);
		Sys.println("origin-present=" + (original.stack.length > 0));
		try {
			try {
				throw original;
			} catch (first:haxe.Exception) {
				Sys.println("first-identity=" + (first == original));
				Sys.println("first-origin=" + (CallStack.toString(first.stack) == before));
				throw first;
			}
		} catch (second:haxe.Exception) {
			Sys.println("rethrow-identity=" + (second == original));
			Sys.println("rethrow-origin=" + (CallStack.toString(second.stack) == before));
		}
	}
}
