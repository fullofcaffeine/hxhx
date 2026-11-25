import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	A typing failure that is neither a `TyperError` nor a String still ends the compile with its
	message (haxe_ocaml-rb8ow).

	`Stage3Compiler.runOne`'s typing phases caught only `TyperError` and String. Any other thrown
	value, such as a `haxe.macro.Error` raised by a macro service while a plugin compile types a
	body, escaped the request: the native compiler printed only
	`Fatal error: exception HxRuntime.Hx_exception(_, _)`.

	The test injects a `haxe.Exception` while typing finalizes method inputs, on the no-emit and
	the emitting path, and expects a compile error that names it.
**/
class M14TypingExceptionMessageTest {
	static inline final FIXTURE = "test/fixtures/typing_exception_message";
	static inline final MESSAGE = "injected typing failure";

	static function main():Void {
		for (emit in [false, true]) {
			final label = emit ? "emitting" : "no-emit";
			final arguments = [
				"--hxhx-no-run",
				"--hxhx-out",
				".tmp/m14-typing-exception-message/" + label,
				"-cp",
				FIXTURE,
				"-main",
				"Main"
			];
			if (!emit)
				arguments.unshift("--hxhx-no-emit");
			final context = new FailingTypingContext();
			final code = try Stage3Compiler.runRequest(arguments, context) catch (e:haxe.Exception) {
				context.close(false);
				throw label + ": the typing failure escaped the request: " + e.message;
			};
			final output = context.output.events().map(event -> event.text).join("");
			context.close(code == 0);
			require(context.injected, label + ": the test did not inject its failure");
			require(code != 0, label + ": the compile must fail");
			require(output.indexOf("type failed during") >= 0
				&& output.indexOf(MESSAGE) >= 0, label + ": the error must name the failure:\n" + output);
		}
		Sys.println("M14_TYPING_EXCEPTION_MESSAGE:PASS");
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}
}

/** Throws a `haxe.Exception` from the typing checkpoint that runs inside method-input finalization. */
private class FailingTypingContext extends CompilationRequestContext {
	public var injected = false;

	public function new() {
		super(0, true, false);
	}

	override public function checkpoint(stage:String):Bool {
		if (stage == "typing" && !injected && Std.string(haxe.CallStack.callStack()).indexOf("TyMethodInputPublication") >= 0) {
			injected = true;
			throw new haxe.Exception(MESSAGE);
		}
		return super.checkpoint(stage);
	}

	static inline final MESSAGE = "injected typing failure";
}
