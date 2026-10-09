import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Execute break and continue in value-producing conditional branches without changing loop ownership. */
class M14SourceLoopControlTest {
	/** A function created inside a loop cannot break or continue its creator's loop. */
	static function checkFunctionBoundary():Void {
		for (operation in ["break", "continue"]) {
			final source = 'class Boundary { static function main():Void { while (true) { var callback = function():Void { $operation; }; } } }';
			final resolved = new ResolvedModule("Boundary", "Boundary.hx", ParserStage.parse(source, "Boundary.hx"));
			var rejected = false;
			try {
				TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			} catch (error:TyperError) {
				if (error.toString().indexOf("loop control requires an enclosing loop in the same function") < 0)
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw "a nested function acquired its creator's loop destination";
		}
	}

	public static function run():Void {
		checkFunctionBoundary();
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/source_loop_control_seed/src", mainModule: "Main", requiredModules: ["Sys"]});
		final typed = fixture.main;
		final functions = typed.getTypedClasses()[0].getFunctions();
		final loop = functions[0].getBody().getStatements()[1];
		final target = loop.getControlTarget();
		final selected = loop.getStatements()[0].getStatements()[1].getExpressions()[0];
		final continued = selected.getExpressions()[1].getExpressions()[0];
		final broken = selected.getExpressions()[2].getExpressions()[1].getExpressions()[0];
		if (target == null
			|| continued.getTag() != ContinueExpr
			|| broken.getTag() != BreakExpr
			|| continued.getControlTarget() != target
			|| broken.getControlTarget() != target)
			throw "source group loop control lost the exact enclosing statement destination";
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final changedScope = new TyControlScope(functions[0].getStableIdentity(), "different-source-revision");
		final changedLoop = changedScope.enter(Loop, target.getSourceIdentity());
		final changedStatements = functions[0].getBody().getStatements();
		changedStatements[1] = loop.withControlTarget(changedLoop);
		final changedFunction = functions[0].withBody(new TypedFunctionBody(changedStatements, functions[0].getBody().getSourceFingerprint()));
		if (CompilerTypedTreeRevision.functionBody(changedFunction) == revisions[0])
			throw "changing a loop destination did not invalidate the typed function revision";
		var rejectedRetarget = false;
		try {
			TypedControlLowering.functionBody(changedFunction);
		} catch (error:String) {
			if (error.indexOf("loop control lowering cannot change its typed loop destination") < 0)
				throw error;
			rejectedRetarget = true;
		}
		if (!rejectedRetarget)
			throw "lowering silently redirected loop control after its loop destination changed";
		final context = new BackendContext(".tmp/source-loop-control", null, "Main", true, true, fixture.defines);
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture), context);
		if (!result.builtExecutable)
			throw "loop control requires a native executable";
		for (i in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
				throw "loop lowering changed the original typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent("test/oracle/source_loop_control_seed/expected.stdout"))
			throw "loop control changed observed behavior: " + stdout + stderr;
		Sys.println("SOURCE_LOOP_NATIVE:PASS");
	}

	static function main():Void
		run();
}
