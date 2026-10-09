package haxe;

/**
	Exception policy for the standalone managed C++ target.
	Instances use ordinary Haxe class storage, including previous-exception and
	native-value links. NativeStackTrace supplies only stack capture/conversion;
	an unavailable primitive must fail target admission instead of inventing an
	empty stack. The compiler bundles this source with its native runtime version.
 */
class Exception {
	public var message(get, never):String;
	public var stack(get, never):CallStack;
	public var previous(get, never):Null<Exception>;
	public var native(get, never):Any;

	final messageValue:String;
	final previousValue:Null<Exception>;
	// Any is required by the public exception API: thrown values retain their
	// original Haxe type and identity. Only checked exception recognition below
	// narrows this value; message conversion never replaces the stored payload.
	final nativeValue:Any;
	final nativeStack:Any;
	var skippedFrames:Int = 0;

	public function new(message:String, ?previous:Exception, ?native:Any):Void {
		messageValue = message;
		previousValue = previous;
		if (native == null) {
			nativeValue = this;
			nativeStack = NativeStackTrace.callStack();
			skippedFrames = 1;
		} else {
			nativeValue = native;
			nativeStack = NativeStackTrace.exceptionStack();
		}
	}

	/** Preserve an existing exception; wrap other caught values exactly once. */
	static function caught(value:Any):Exception {
		if (Std.isOfType(value, Exception)) {
			// The runtime type check above establishes the public API's Any boundary.
			final existing:Exception = cast value;
			return existing;
		}
		return new ValueException(value);
	}

	/** Keep native origin identity when an exception crosses another throw. */
	static function thrown(value:Any):Any {
		if (Std.isOfType(value, Exception)) {
			// Narrow only after the runtime check; never reconstruct from message text.
			final existing:Exception = cast value;
			return existing.native;
		}
		return value;
	}

	function unwrap():Any
		return nativeValue;

	public function toString():String
		return messageValue;

	/** Include chained exceptions while removing the shared tail of adjacent stacks. */
	public function details():String {
		var result = "";
		var current:Null<Exception> = this;
		var next:Null<Exception> = null;
		while (current != null) {
			final frames = next == null ? current.stack : @:privateAccess current.stack.subtract(next.stack);
			result = "Exception: " + current.message + frames + (next == null ? "" : "\n\nNext ") + result;
			next = current;
			current = current.previous;
		}
		return result;
	}

	/** Called by derived constructors to keep their construction frames out of the public stack. */
	function __shiftStack():Void
		skippedFrames++;

	function get_message():String
		return messageValue;

	function get_stack():CallStack
		return NativeStackTrace.toHaxe(nativeStack, skippedFrames);

	function get_previous():Null<Exception>
		return previousValue;

	final function get_native():Any
		return nativeValue;
}
