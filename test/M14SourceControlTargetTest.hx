/** Exact return and loop targets must survive lexical scopes, replay, inference copies, and typed rebuilds. */
class M14SourceControlTargetTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function reject(action:Void->Void, fragment:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(fragment) >= 0)
				return;
			throw error;
		}
		throw "expected rejection: " + fragment;
	}

	static function main():Void {
		final controls = new TyControlScope("Main.choose", "source-revision-1");
		final environment = new TyFunctionEnv("choose", [], [], TyType.unknown(), TyType.unknown(), "Main.choose", null, false, 0, false, controls);
		final root = controls.returnTarget();
		environment.enterLexicalScope();
		require(controls.returnTarget() == root, "a value block changed the enclosing return target");
		final outerLoop = controls.enter(Loop, "outer-loop");
		require(controls.returnTarget() == root && controls.loopTarget() == outerLoop, "loop changed return ownership");
		final nested = controls.enter(Function, "callback");
		require(controls.returnTarget() == nested && controls.loopTarget() == null, "nested function inherited an enclosing loop");
		final innerLoop = controls.enter(Loop, "inner-loop");
		require(controls.loopTarget() == innerLoop, "inner loop target was not selected");
		controls.exit(innerLoop);
		controls.exit(nested);
		controls.exit(outerLoop);
		environment.exitLexicalScope();

		final replayEnvironment = environment.withReturnTypes(TyType.fromHintText("Int"), TyType.fromHintText("Int")).createBodyReplay();
		final replay = replayEnvironment.requireControlScope();
		require(replay.getRoot() == root, "replay reconstructed the root target");
		require(replay.enter(Loop, "outer-loop") == outerLoop, "replay reconstructed a loop target");
		require(replay.enter(Function, "callback") == nested, "replay reconstructed a function target");
		final speculative = replayEnvironment.copyForInference().requireControlScope();
		final ignored = speculative.enter(Function, "speculative-only");
		speculative.exit(ignored);
		require(replay.enter(Loop, "inner-loop") == innerLoop, "speculation consumed the replay cursor");
		replay.exit(innerLoop);
		replay.exit(nested);
		replay.exit(outerLoop);
		replayEnvironment.assertReplayComplete();

		final wrongParent = controls.createReplay();
		wrongParent.enter(Loop, "outer-loop");
		wrongParent.exit(outerLoop);
		reject(() -> {
			wrongParent.enter(Function, "callback");
		}, "replay differs");
		final incomplete = controls.createReplay();
		reject(() -> incomplete.assertReplayComplete(), "did not consume");

		final returned = TypedExpr.returnExpr(TypedExpr.intLiteral(7, TyType.fromHintText("Int"), null), TyType.noNormalCompletion(), null)
			.withControlTarget(root);
		final rebuilt = returned.withExpressions(returned.getExpressions()).withType(returned.getType()).withCatchUses([]);
		require(rebuilt.getControlTarget() == root, "typed rebuild lost the exact return target");
		reject(() -> {
			returned.withControlTarget(outerLoop);
		}, "requires a function target");
		final continued = TypedStmt.continueStmt(null).withControlTarget(outerLoop);
		final rebuiltContinue = continued.withChildren([], []).withCatchUses([]);
		require(rebuiltContinue.getControlTarget() == outerLoop, "statement rebuild lost the selected loop destination");
		final loop = TypedStmt.whileStmt(TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), null), continued, null).withControlTarget(outerLoop);
		require(loop.withChildren(loop.getExpressions(), loop.getStatements()).getControlTarget() == outerLoop,
			"loop statement rebuild lost its own destination");
		reject(() -> {
			continued.withControlTarget(root);
		}, "requires a loop target");
		reject(() -> {
			TypedStmt.block([], null).withControlTarget(outerLoop);
		}, "cannot carry a control target");
		final differentRevision = new TyControlScope("Main.choose", "source-revision-2");
		require(CompilerTypedTreeRevision.expression("Main.choose",
			returned) != CompilerTypedTreeRevision.expression("Main.choose", returned.withControlTarget(differentRevision.getRoot())),
			"source revision change did not invalidate a typed control target");
		Sys.println("SOURCE_CONTROL_TARGET:PASS");
	}
}
