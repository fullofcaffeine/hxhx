import sys.io.File;
import backend.BackendContext;
import backend.BackendRegistry;

/** Compare authored switch guards with independently specified upstream and native output. */
class M14Stage3SwitchGuardTest {
	static function main():Void {
		final root = "test/fixtures/stage3_switch_guard";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("SWITCH_GUARD_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final functions = [for (owner in typed.getTypedClasses()) for (fn in owner.getFunctions()) fn];
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		for (fn in functions) {
			final lowered = TypedControlLowering.functionBody(fn);
			if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
				throw "repeated guard lowering changed case execution";
		}
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-switch-guard", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		final result = BackendRegistry.requireForTarget("js-native")
			.emit(MacroStage.expandProgram([typed], []),
				new BackendContext(".tmp/switch-guard-js-native", null, "Main", true, false, new haxe.ds.StringMap<String>()));
		M14Stage3RuntimeFixture.observe({command: "node", arguments: [result.entryPath], expected: expected});
		Sys.println("SWITCH_GUARD_JS:PASS");
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "guard lowering changed the authored typed source";
		Sys.println("SWITCH_GUARD_NATIVE:PASS");
		var rejected = false;
		try {
			M14Stage3RuntimeFixture.typeMain({
				source: "class Main { static function main() { switch 1 { case 1 if (3): 7; case _: 9; } } }",
				path: path,
				root: root
			});
		} catch (error:TyperError) {
			rejected = Std.string(error).indexOf("should be Bool") >= 0;
		}
		if (!rejected)
			throw "non-Boolean switch guard was accepted";
		Sys.println("SWITCH_GUARD_TYPE_REJECTION:PASS");
		final sourceTrue = HxParser.parseCompleteExprText("switch 1 { case 1 if (true): 7; case _: 9; }");
		final sourceFalse = HxParser.parseCompleteExprText("switch 1 { case 1 if (false): 7; case _: 9; }");
		final trueTree = TypedBodyBuilder.buildExpression(sourceTrue, HxPos.unknown(), null);
		final falseTree = TypedBodyBuilder.buildExpression(sourceFalse, HxPos.unknown(), null);
		if (TypedBodyFingerprint.exactExpression(sourceTrue) != TypedBodyFingerprint.exactExpression(TypedSourceSyntax.expression(trueTree)))
			throw "typed source reconstruction changed the authored guard";
		if (CompilerTypedTreeRevision.expression("guard", trueTree) == CompilerTypedTreeRevision.expression("guard", falseTree))
			throw "guard changes did not invalidate the typed revision";
		var seenGuard = false;
		TypedBackendSourceWalk.expression(sourceTrue, value -> switch value {
			case EBool(true): seenGuard = true;
			case _:
		});
		if (!seenGuard)
			throw "source traversal omitted the guard expression";
		Sys.println("SWITCH_GUARD_SOURCE_REVISION:PASS");
	}
}
