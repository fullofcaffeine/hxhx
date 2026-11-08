import backend.BackendContext;
import backend.BackendRegistry;
import sys.io.File;

/**
	Prove that an `if`/`else` written inside a switch case keeps both branches.

	The parser represents a case body as a source group whose expressions keep
	their authored shape (`ESourceIf`, `ETernary`), so this test first checks that
	shape directly. It then runs one fixture through upstream Haxe (`--interp`),
	native Stage3 OCaml, and the native JavaScript backend, and requires the same
	independently recorded stdout from all three. A lost else branch changes the
	printed value, so it cannot hide behind generated-text differences.
 */
class M14Stage3SwitchCaseIfElseIntegrationTest {
	static final root = "test/fixtures/stage3_switch_case_if_else";

	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function isStdString(expr:HxExpr):Bool {
		return switch expr {
			case ECall(EField(EIdent("Std"), "string"), [EIdent("t")]): true;
			case _: false;
		};
	}

	/** The expression-if after a local declaration is the shape DateTools uses. */
	static function assertParserKeepsElseBranch():Void {
		final expr = HxParser.parseCompleteExprText('switch (e) { case "u": var t = d.getDay(); if (t == 0) "7" else Std.string(t); }');
		final ok = switch expr {
			case ESwitch(_, [PString("u")], [ESourceGroup([EVars(_), ESourceIf(_, EString("7"), elseBranch, _)], _)]):
				isStdString(elseBranch);
			case _:
				false;
		}
		assertTrue(ok, 'Parser dropped the expression-if else branch inside a switch case: ' + Std.string(expr));
	}

	/** A semicolon before `else` is accepted in a case body exactly as in a block. */
	static function assertParserKeepsStatementElse():Void {
		final inCase = HxParser.parseCompleteExprText('switch x { case 1: if (c) a(); else Std.string(t); case _: }');
		final caseOk = switch inCase {
			case ESwitch(_, _, [ESourceGroup([ESourceIf(_, ECall(EIdent("a"), []), elseBranch, _)], _), _]): isStdString(elseBranch);
			case _: false;
		}
		assertTrue(caseOk, 'Parser dropped a statement else branch inside a switch case: ' + Std.string(inCase));
		final inBlock = HxParser.parseCompleteExprText('{ if (c) a(); else Std.string(t); }');
		final blockOk = switch inBlock {
			case ESourceGroup([ESourceIf(_, ECall(EIdent("a"), []), elseBranch, _)], _): isStdString(elseBranch);
			case _: false;
		}
		assertTrue(blockOk, 'Parser dropped a statement else branch inside a block: ' + Std.string(inBlock));
	}

	static function main():Void {
		assertParserKeepsElseBranch();
		assertParserKeepsStatementElse();
		Sys.println("SWITCH_CASE_IF_ELSE_PARSER:PASS");

		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("SWITCH_CASE_IF_ELSE_UPSTREAM:PASS");

		final path = root + "/Main.hx";
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-switch-case-if-else");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("SWITCH_CASE_IF_ELSE_NATIVE:PASS");

		final result = BackendRegistry.requireForTarget("js-native")
			.emit(MacroStage.expandProgram([typed], []),
				new BackendContext(".tmp/switch-case-if-else-js-native", null, "Main", false, new haxe.ds.StringMap<String>()));
		M14Stage3RuntimeFixture.observe({command: "node", arguments: [result.entryPath], expected: expected});
		Sys.println("SWITCH_CASE_IF_ELSE_JS:PASS");
	}
}
