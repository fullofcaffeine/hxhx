/** A projected loop and its jumps retain exact ownership through the shared statement boundary. */
class M14StatementControlProjectionTest {
	static function rejects(action:Void->Void, fragment:String):Void {
		try {
			action();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "invalid statement control was accepted";
	}

	public static function main():Void {
		final source = 'class Main {static function run():Int {var count=0; for (i in 0...3) {if (i==1) continue; count++; if (i==2) break;} return count;}}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final fn = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0].getFunctions()[0];
		final projection = TypedBodySource.functionProjection(fn);
		final foreign = TypedBodySource.functionProjection(fn);
		var exits = 0;
		var loop:Null<HxStmt> = null;
		var target = "";
		for (statement in projection.getBody())
			TypedBackendSourceWalk.statement(statement, _ -> {}, entry -> {
				switch entry {
					case SForIn(name, iterable, body, position):
						loop = entry;
						final fact = projection.requireStatementControl(entry);
						target = fact.destination;
						rejects(() -> foreign.requireStatementControl(entry), "absent from this exact function projection");
						rejects(() -> projection.requireStatementControl(SForIn(name, iterable, body, position)), "absent from this exact function projection");
						rejects(() -> fact.assertCurrent("foreign", projection.getBodyRevision()), "another executable or revision");
						rejects(() -> fact.assertCurrent(projection.getStableIdentity(), "foreign"), "another executable or revision");
					case SBreak(_) | SContinue(_):
						if (projection.requireStatementControl(entry).destination != target)
							throw "jump lost its exact loop destination";
						exits++;
					case _:
				}
			});
		if (loop == null || exits != 2)
			throw "control observer lost its loop or exits";
		final selected = projection.requireStatementControl(loop);
		switch loop {
			case SForIn(_, _, SBlock(children, position), _):
				children.push(SExpr(EInt(8), position));
			case _:
				throw "mutation observer requires the original loop block";
		}
		rejects(() -> selected.assertCurrent(projection.getStableIdentity(), projection.getBodyRevision()), "changed after projection");
		// The public accessor must also reject the changed body before returning facts.
		var rejected = false;
		try {
			projection.requireStatementControl(loop);
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw "changed loop retained projection authority";
		Sys.println("STATEMENT_CONTROL_PROJECTION:PASS");
	}
}
