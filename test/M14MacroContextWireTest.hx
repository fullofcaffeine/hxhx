import haxe.macro.Expr;
import hxhx.macro.InProcMacroSession;
import hxhx.macro.MacroContextHostServices;
import hxhx.macro.MacroState;
import hxhxmacrohost.MacroContextAbort;
import hxhxmacrohost.MacroContextWire;
import hxhxmacrohost.MacroSyntaxWire;

/**
	The macro Context host service (Context PR 1) without a native plugin.

	A plugin's `haxe.macro.Context` encodes a request (`MacroContextWire`), the compiler answers it
	(`MacroContextHostServices`), and the plugin decodes the answer. This test drives both halves
	directly. The native round trip, with upstream Haxe 4.3.7's output, is
	`npm run test:macro-runtime:project-module` (fixture `test/fixtures/project-macro-context`).
**/
class M14MacroContextWireTest {
	static final fixture = "test/fixtures/project-macro-context";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function position(file:String, min:Int, max:Int):Position
		return {file: file, min: min, max: max};

	static function samePosition(actual:Position, expected:Position):Bool
		return actual.file == expected.file && actual.min == expected.min && actual.max == expected.max;

	/** A String failure thrown by a plugin-side decoder, or null when none was thrown. */
	static function failureOf(run:() -> Void):Null<String> {
		try {
			run();
		} catch (error:String) {
			return error;
		}
		return null;
	}

	static function main():Void {
		// The compilation's defines, as `Stage3Compiler` seeds them from `-D`.
		MacroState.reset();
		MacroState.seedFromCliDefines(["probe_flag", "probe_dashed", "probe_value=forty-two"]);
		final call = position("src/Main.hx", 41, 41);
		final services = MacroContextHostServices.forCall("src/Main.hx", new HxPos(41, 3, 15));
		final answer = (request:String) -> MacroContextHostServices.handle(services, request);

		// Positions and defines: the values upstream Haxe 4.3.7 gives in expected.stdout.
		require(samePosition(MacroContextWire.readPosition(answer(MacroContextWire.requestCurrentPos())), call), "currentPos");
		require(MacroContextWire.readBool(answer(MacroContextWire.requestDefined("probe_flag"))), "defined(probe_flag)");
		require(MacroContextWire.readBool(answer(MacroContextWire.requestDefined("probe-dashed"))), "defined(probe-dashed) converts `-` to `_`");
		require(!MacroContextWire.readBool(answer(MacroContextWire.requestDefined("probe_missing"))), "defined(probe_missing)");
		require(MacroContextWire.readOptionalString(answer(MacroContextWire.requestDefinedValue("probe_value"))) == "forty-two", "definedValue");
		require(MacroContextWire.readOptionalString(answer(MacroContextWire.requestDefinedValue("probe_flag"))) == "1", "definedValue of a flag");
		require(MacroContextWire.readOptionalString(answer(MacroContextWire.requestDefinedValue("probe_missing"))) == null, "an undefined value is null");

		// parse and parseInlineString: one expression, every position the one the macro passed.
		final at = position("src/Main.hx", 10, 20);
		for (inlined in [false, true]) {
			final parsed = MacroContextWire.readExpr(answer(MacroContextWire.requestParse("[1, 2, 3].length + 40", at, inlined)));
			require(samePosition(parsed.pos, at), "parsed root position");
			switch parsed.expr {
				case EBinop(OpAdd, left, right):
					require(samePosition(left.pos, at) && samePosition(right.pos, at), "parsed child positions");
				case other:
					throw "unexpected parsed shape " + other;
			}
		}

		// Invalid code is a Context error at the given position; the plugin stops the macro there.
		var aborted:Null<MacroContextAbort> = null;
		try {
			MacroContextWire.readExpr(answer(MacroContextWire.requestParse("1 +", at, false)));
		} catch (abort:MacroContextAbort) {
			aborted = abort;
		}
		require(aborted != null && samePosition(aborted.position, at), "a parse error did not stop the macro at its position");

		// A service this version does not provide, and a malformed request.
		final unsupported = failureOf(() -> MacroContextWire.readBool(answer(MacroContextWire.VERSION + "\nCS12:context.nope")));
		require(unsupported != null
			&& unsupported.indexOf("macro context: unsupported: Context service `context.nope`") == 0, "unsupported: " + unsupported);
		final invalid = failureOf(() -> MacroContextWire.readBool(answer("not a request")));
		require(invalid != null && invalid.indexOf("macro context: invalid:") == 0, "invalid: " + invalid);
		final missing = failureOf(() -> MacroContextWire.readBool(""));
		require(missing != null && missing.indexOf("no macro context service") >= 0, "no service: " + missing);

		// The failure envelope carries the position of `Context.error`, or none.
		final reported = MacroSyntaxWire.decodeFailureDetails(MacroSyntaxWire.encodeFailure("context error here", position("src/ErrorMain.hx", 143, 147)));
		require(reported.message == "context error here"
			&& samePosition(reported.position, position("src/ErrorMain.hx", 143, 147)), "failure position");
		require(MacroSyntaxWire.decodeFailureDetails(MacroSyntaxWire.encodeFailure("plain")).position == null, "failure without a position");

		// The compiler prints it as upstream does (expected-error.stderr, from haxe 4.3.7 in the fixture).
		final file = fixture + "/src/ErrorMain.hx";
		final printed = TyperStage.extractRawDiagnostic(InProcMacroSession.reportedAt("context error here", position(file, 143, 147), file).message);
		final upstream = StringTools.trim(sys.io.File.getContent(fixture + "/expected-error.stderr"));
		require(printed == StringTools.replace(upstream, "src/ErrorMain.hx", file), "printed `"
			+ printed
			+ "`, upstream `"
			+ upstream
			+ "`");

		Sys.println("M14_MACRO_CONTEXT_WIRE:PASS");
	}
}
