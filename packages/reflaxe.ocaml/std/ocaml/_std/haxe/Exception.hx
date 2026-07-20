package haxe;

/**
	`haxe.Exception` (OCaml target).

	WHY
	- The upstream Haxe stdlib declares `haxe.Exception` as an `extern`.
	  For Reflaxe custom targets that means no runtime module is emitted unless we
	  provide one.
	- `haxe.ValueException` extends `haxe.Exception` and expects a real base class
	  implementation for `super(...)` lowering.

	WHY THIS LIVES UNDER `std/ocaml/_std`
	- This is a normal OCaml stdlib override in the Reflaxe-generated source
	  layout: `std` contains target APIs, and `std/ocaml/_std` contains target
	  replacements for upstream stdlib modules.
	- Local source builds receive this directory through explicit dev/test
	  classpaths, matching Reflaxe's generated-compiler workflow.
	- Published haxelib packages are flattened by `haxelib run reflaxe build`;
	  this source file becomes `src/haxe/Exception.cross.hx` in that package.
	- The internal `#if ocaml_output` keeps the real implementation target-gated
	  even in flattened packages where `.cross.hx` is visible to custom targets.
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
	// Keep the default implicit while the typed-body lifecycle repair is in
	// progress. This source shape moved an earlier failure but does not fix the
	// actual defect: a later Reflaxe cleanup can discard the target-owned origin
	// while retaining the feature-gated assignment or update itself.
	@:noCompletion @:ifFeature("haxe.Exception.get_stack") var __skipStack:Int;
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
		if (previous == null)
			return 'Exception: ${toString()}${stack}';
		var result = '';
		var current:Null<Exception> = this;
		var prev:Null<Exception> = null;
		while (current != null) {
			if (prev == null) {
				result = 'Exception: ${current.message}${current.stack}' + result;
			} else {
				final prevStack = @:privateAccess current.stack.subtract(prev.stack);
				result = 'Exception: ${current.message}${prevStack}\n\nNext ' + result;
			}
			prev = current;
			current = current.previous;
		}
		return result;
	}

	@:noCompletion
	@:ifFeature("haxe.Exception.get_stack")
	// Keep both stack helpers as real calls while the typed-body lifecycle repair
	// is in progress. This source shape moved an earlier failure, but Haxe's
	// built-in post-DCE constructor work completes before Reflaxe preprocessing.
	// The remaining defect is loss of the target-owned origin inside that
	// preprocessing lifecycle, not late Haxe inlining.
	function __shiftStack():Void {
		__skipStack++;
	}

	@:noCompletion
	@:ifFeature("haxe.Exception.get_stack")
	function __unshiftStack():Void {
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
