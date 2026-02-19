package haxe;

/**
	`haxe.Exception` (OCaml target).

	WHY
	- The upstream Haxe stdlib declares `haxe.Exception` as an `extern`.
	  For Reflaxe custom targets that means no runtime module is emitted unless we
	  provide one.
	- `haxe.ValueException` extends `haxe.Exception` and expects a real base class
	  implementation for `super(...)` lowering.

	WHY THIS LIVES UNDER `src/`
	- Some stdlib modules are needed early during compilation (before bootstrap
	  macros can inject `std/` and `std/_std/`).
	- Like `haxe.elixir`, we use a `.cross.hx` + `#if ocaml_output` gate:
	  - When compiling to OCaml (`-D ocaml_output=...`), emit the real implementation.
	  - Otherwise, expose only an `extern` surface so other targets/tools don’t
		pull OCaml-only code (and don’t generate references to OCaml runtime modules).
**/
@:coreApi
#if ocaml_output
class Exception {
	public var message(get, never):String;
	public var stack(get, never):CallStack;
	public var previous(get, never):Null<Exception>;
	public var native(get, never):Any;

	@:noCompletion var __exceptionMessage:String;
	@:noCompletion var __exceptionStack:Null<CallStack>;
	@:noCompletion var __nativeStack:Any;
	@:noCompletion @:ifFeature("haxe.Exception.get_stack") var __skipStack:Int = 0;
	@:noCompletion var __nativeException:Any;
	@:noCompletion var __previousException:Null<Exception>;

	static function caught(value:Any):Exception {
		// NOTE: We intentionally avoid referencing `haxe.ValueException` here to prevent
		// an OCaml module dependency cycle (`haxe.ValueException` extends `haxe.Exception`).
		//
		// The OCaml backend itself wraps non-Exception throws into `haxe.ValueException`
		// when lowering `catch(e:haxe.Exception)` / `catch(e:haxe.ValueException)`.
		return Std.isOfType(value, Exception) ? (value : Exception) : new Exception(Std.string(value), null, value);
	}

	static function thrown(value:Any):Any {
		return Std.isOfType(value, Exception) ? (value : Exception).native : value;
	}

	public function new(message:String, ?previous:Exception, ?native:Any) {
		__exceptionMessage = message;
		__previousException = previous;
		if (native != null) {
			__nativeStack = NativeStackTrace.exceptionStack();
			__nativeException = native;
		} else {
			__nativeStack = NativeStackTrace.callStack();
			__shiftStack();
			__nativeException = this;
		}
	}

	function unwrap():Any {
		return __nativeException;
	}

	public function toString():String {
		return message;
	}

	public function details():String {
		return inline CallStack.exceptionToString(this);
	}

	@:noCompletion
	@:ifFeature("haxe.Exception.get_stack")
	inline function __shiftStack():Void {
		__skipStack++;
	}

	@:noCompletion
	@:ifFeature("haxe.Exception.get_stack")
	inline function __unshiftStack():Void {
		__skipStack--;
	}

	function get_message():String {
		return __exceptionMessage;
	}

	function get_previous():Null<Exception> {
		return __previousException;
	}

	final function get_native():Any {
		return __nativeException;
	}

	function get_stack():CallStack {
		return switch __exceptionStack {
			case null:
				__exceptionStack = NativeStackTrace.toHaxe(__nativeStack, __skipStack);
			case s: s;
		}
	}
}
#else
extern class Exception {
	public var message(get, never):String;
	private function get_message():String;

	public var stack(get, never):CallStack;
	private function get_stack():CallStack;

	public var previous(get, never):Null<Exception>;
	private function get_previous():Null<Exception>;

	public var native(get, never):Any;
	final private function get_native():Any;

	static private function caught(value:Any):Exception;
	static private function thrown(value:Any):Any;

	public function new(message:String, ?previous:Exception, ?native:Any):Void;
	private function unwrap():Any;
	public function toString():String;
	public function details():String;
}
#end
