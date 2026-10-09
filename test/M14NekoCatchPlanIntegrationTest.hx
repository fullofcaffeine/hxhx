import backend.vm.NekoCatchPlan;
import backend.vm.NekoExecutableProjection;
import backend.vm.NekoTypedProgramProjection;

/** Checks ordered catch bindings from real typed source and rejects foreign or non-catch locals. */
class M14NekoCatchPlanIntegrationTest {
	static function expectFailure(fragment:String, action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(fragment) < 0)
				throw "unexpected catch-plan error: " + error.message;
			return;
		}
		throw "missing catch-plan rejection: " + fragment;
	}

	static function main():Void {
		final source = 'class Main {
public var observed:String = try "ok" catch (error:String) error;
static function check(parameter:Int):Void {
try { throw 7; } catch (text:String) {} catch (number:Int) {}
var result = try 7 catch (number:Int) number;
} }';
		final module = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.project(source);
		final program = new NekoTypedProgramProjection("neko-catch-plan-test", [module]);
		final owner = program.requireClass("Main");
		final bodies = owner.getFunctions();
		final body = bodies[0];
		if (HxFunctionDecl.getName(body.getDeclaration()) != "check")
			throw "fixture did not select the authored function";
		final selected = FunctionBody(program.requireDeclaredFunction(body.getDeclaration()));
		final statement = body.getBody()[0];
		final clauses = switch (statement) {
			case STry(_, clauses, _): clauses;
			case _: throw "fixture lost its statement try";
		};
		final plan = NekoCatchPlan.forStatement(program, selected, statement);
		expectFailure("shared implicit-use facts", () -> plan.validate(program));
		expectFailure("body revision", () -> program.requireCatchCatalog(selected).assertOwner(body.getStableIdentity(), "changed-body"));
		if (plan.executableIdentity != body.getStableIdentity() || plan.bodyRevision != body.getBodyRevision())
			throw "catch plan lost the enclosing typed body";
		final types = [
			for (entry in plan.getCases())
				entry.local.getBinding().getType().getSemanticKey()
		];
		if (types.join(",") != "primitive:String,primitive:Int")
			throw "catch plan changed source order or exact types: " + types.join(",");
		final expressionStatement = body.getBody()[2];
		final expressionPlan = NekoCatchPlan.forStatement(program, selected, expressionStatement);
		final expressionBinding = expressionPlan.getCases()[0].local;
		if (expressionBinding.getBinding().getType().getSemanticKey() != "primitive:Int"
			|| expressionBinding.getProjectedName() == plan.getCases()[1].local.getProjectedName())
			throw "separate same-named catches lost their distinct typed bindings";
		if (plan.occurrenceIdentity == expressionPlan.occurrenceIdentity)
			throw "separate try occurrences received the same identity";
		if (NekoCatchPlan.forStatement(program, selected, statement) != plan)
			throw "catch lookup rebuilt its prepared plan";
		expectFailure("exact current executable", () -> NekoCatchPlan.forStatement(program, null, statement));
		final copied = switch (statement) {
			case STry(tryBody, catches, pos): HxStmt.STry(tryBody, catches.copy(), pos);
			case _: throw "missing try";
		};
		expectFailure("owned statement occurrence", () -> NekoCatchPlan.forStatement(program, selected, copied));
		expectFailure("owned expression occurrence", () -> NekoCatchPlan.forExpression(program, selected, EIdent("not-a-handler")));
		clauses.reverse();
		expectFailure("changed after preparation", () -> NekoCatchPlan.forStatement(program, selected, statement));
		clauses.reverse();
		final repeated = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.project(source);
		final foreignProgram = new NekoTypedProgramProjection("neko-catch-plan-test", [repeated]);
		final foreign = FunctionBody(foreignProgram.requireDeclaredFunction(foreignProgram.requireClass("Main").getFunctions()[0].getDeclaration()));
		expectFailure("cannot identify projected function", () -> NekoCatchPlan.forStatement(program, foreign, statement));
		final initializer = owner.getFieldInitializers()[0];
		final initializerTries = new Array<HxExpr>();
		TypedBackendSourceWalk.expression(initializer.getExpression(), node -> {
			if (node.match(ELoweredControl(Try(_), _, _, _)))
				initializerTries.push(node);
		});
		if (initializerTries.length != 1)
			throw "fixture lost its initializer try";
		final initializerPlan = NekoCatchPlan.forExpression(program, FieldInitializer(initializer), initializerTries[0]);
		if (initializerPlan.executableIdentity != initializer.getStableIdentity()
			|| initializerPlan.bodyRevision != initializer.getBodyRevision()
			|| initializerPlan.getCases()[0].local.getBinding().getType().getSemanticKey() != "primitive:String")
			throw "initializer catch lost its exact owner or binding type";
		final catalog = program.requireCatchCatalog(FieldInitializer(initializer));
		final adapted = new Array<HxStmt>();
		TypedControlStatements.initializerBody(initializer.getExpression(), initializer.getStableIdentity(), (source, statement) -> {
			@:privateAccess catalog.recordAdaptation(source, statement);
			adapted.push(statement);
		});
		if (adapted.length != 1)
			throw "adapter lost exact catch provenance";
		final adaptedPlan = catalog.forStatement(adapted[0]);
		if (adaptedPlan.occurrenceIdentity != initializerPlan.occurrenceIdentity
			|| adaptedPlan.getCases()[0].local != initializerPlan.getCases()[0].local)
			throw "adaptation replaced the catch owner or binding";
		switch adapted[0] {
			case STry(tryBody, catches, position):
				expectFailure("owned statement occurrence", () -> catalog.forStatement(STry(tryBody, catches.copy(), position)));
				switch catches[0].body {
					case SBlock(nodes, _):
						nodes.push(SExpr(ENull, HxPos.unknown()));
						expectFailure("changed after preparation", () -> catalog.forStatement(adapted[0]));
						nodes.pop();
					case _: throw "adapted handler lost its lexical scope";
				}
			case _:
				throw "adapter did not produce an exact try statement";
		}
		switch initializerTries[0] {
			case ELoweredControl(kind, owner, entries, position):
				expectFailure("owned expression occurrence", () -> catalog.forExpression(ELoweredControl(kind, owner, entries.copy(), position)));
				switch entries[1] {
					case ELoweredControl(Scope, _, nodes, _):
						nodes.push(ENull);
						expectFailure("changed after preparation", () -> catalog.forStatement(adapted[0]));
						nodes.pop();
					case _: throw "lowered handler lost its lexical scope";
				}
				entries.push(ENull);
				expectFailure("changed after preparation", () -> catalog.forStatement(adapted[0]));
				entries.pop();
			case _:
				throw "missing lowered try";
		}
		final foreignInitializer = foreignProgram.requireClass("Main").getFieldInitializers()[0];
		expectFailure("initializer", () -> NekoCatchPlan.forExpression(program, FieldInitializer(foreignInitializer), initializer.getExpression()));
		final duplicateModule = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.project(source);
		switch (duplicateModule.getClasses()[0].getFunctions()[0].getBody()[0]) {
			case STry(_, catches, _):
				catches.push(catches[0]);
			case _:
				throw "missing duplicate fixture";
		}
		expectFailure("duplicate catch binding", () -> new NekoTypedProgramProjection("duplicate", [duplicateModule]));
		Sys.println("NEKO_CATCH_PLAN:PASS");
	}
}
