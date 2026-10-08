#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;

using reflaxe.helpers.ClassFieldHelper;
#end

/** Gives native component tests the production catalog and final-body return decisions. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckOcamlCallableReturnPlan {
	/** Each factory is selected and checked by the same planners used during source compilation. */
	public static macro function selected(fieldName:String):haxe.macro.Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback fixture";
		};
		final field = Lambda.find(owner.statics.get(), field -> field.name == fieldName);
		if (field == null)
			throw "callback fixture has no requested method";
		final programRevision = "callback-return-fixture-program";
		final compiler = new OcamlCompiler();
		compiler.functionPlanRegistry.beginProgram(programRevision);
		compiler.representationRegistry.beginProgram(programRevision);
		compiler.planCallableDeclarations([owner.module], [owner.module => [owner]], programRevision);
		final data = field.findFuncData(owner, true);
		if (data == null)
			throw "callback fixture has no typed function body";
		data.bindProgramRevision(programRevision);
		final binding = compiler.functionPlanRegistry.planningBindingFor(data);
		final planner = new OcamlCallPlanner(compiler.representationRegistry, binding, null, null, null, compiler.functionPlanRegistry.callableDeclaration);
		final boundary = planner.boundaryFor(data);
		if (boundary == null || boundary.callbackReturns == null || boundary.callbackReturns.length != 1)
			throw "production planner did not seal exactly one callback return";
		OcamlCallPlan.requireCallableBoundary(boundary);
		return Context.makeExpr(boundary.callbackReturns[0], Context.currentPos());
	}
}
