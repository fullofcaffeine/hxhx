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
		final clauses = switch (body.getBody()[0]) {
			case STry(_, clauses, _): clauses;
			case _: throw "fixture lost its statement try";
		};
		final plan = NekoCatchPlan.forStatement(program, selected, clauses);
		if (plan.executableIdentity != body.getStableIdentity() || plan.bodyRevision != body.getBodyRevision())
			throw "catch plan lost the enclosing typed body";
		final types = [
			for (entry in plan.getCases())
				entry.local.getBinding().getType().getSemanticKey()
		];
		if (types.join(",") != "primitive:String,primitive:Int")
			throw "catch plan changed source order or exact types: " + types.join(",");
		final expressions = switch (body.getBody()[1]) {
			case SVar(_, _, ECall(EIdent("__hxhx_try"), [_, EArrayDecl(entries), ENull]), _): entries;
			case other: throw "fixture lost its expression try: " + Std.string(other);
		};
		final expressionPlan = NekoCatchPlan.forExpression(program, selected, expressions);
		final expressionBinding = expressionPlan.getCases()[0].local;
		if (expressionBinding.getBinding().getType().getSemanticKey() != "primitive:Int"
			|| expressionBinding.getProjectedName() == plan.getCases()[1].local.getProjectedName())
			throw "separate same-named catches lost their distinct typed bindings";
		expectFailure("exact current executable", () -> NekoCatchPlan.forStatement(program, null, clauses));
		expectFailure("duplicate catch binding", () -> NekoCatchPlan.forStatement(program, selected, [clauses[0], clauses[0]]));
		expectFailure("exact catch binding",
			() -> NekoCatchPlan.forStatement(program, selected, [{name: "parameter", typeHint: "Int", body: clauses[0].body}]));
		expectFailure("malformed expression handler", () -> NekoCatchPlan.forExpression(program, selected, [EIdent("not-a-handler")]));
		final repeated = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.project(source);
		final foreignProgram = new NekoTypedProgramProjection("neko-catch-plan-test", [repeated]);
		final foreign = FunctionBody(foreignProgram.requireDeclaredFunction(foreignProgram.requireClass("Main").getFunctions()[0].getDeclaration()));
		expectFailure("cannot identify projected function", () -> NekoCatchPlan.forStatement(program, foreign, clauses));
		final initializer = owner.getFieldInitializers()[0];
		final initializerEntries = switch (initializer.getExpression()) {
			case ECall(EIdent("__hxhx_try"), [_, EArrayDecl(entries), ENull]): entries;
			case _: throw "fixture lost its initializer try";
		};
		final initializerPlan = NekoCatchPlan.forExpression(program, FieldInitializer(initializer), initializerEntries);
		if (initializerPlan.executableIdentity != initializer.getStableIdentity()
			|| initializerPlan.bodyRevision != initializer.getBodyRevision()
			|| initializerPlan.getCases()[0].local.getBinding().getType().getSemanticKey() != "primitive:String")
			throw "initializer catch lost its exact owner or binding type";
		final foreignInitializer = foreignProgram.requireClass("Main").getFieldInitializers()[0];
		expectFailure("initializer", () -> NekoCatchPlan.forExpression(program, FieldInitializer(foreignInitializer), initializerEntries));
		Sys.println("NEKO_CATCH_PLAN:PASS");
	}
}
