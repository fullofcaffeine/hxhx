package backend.vm;

import backend.vm.NekoTypedProgramProjection.NekoProjectedFunction;
import TypedExactStaticCallSource.TypedExactStaticCall;

/** Bind a transported static call to the exact program declaration before reachability or emission. */
class NekoExactStaticCallPlan {
	public final selected:NekoProjectedFunction;
	public final call:TypedExactStaticCall;

	function new(selected:NekoProjectedFunction, call:TypedExactStaticCall) {
		this.selected = selected;
		this.call = call;
	}

	public static function fromExpression(program:NekoTypedProgramProjection, expression:HxExpr):Null<NekoExactStaticCallPlan> {
		final call = TypedExactStaticCallSource.decode(expression);
		if (call == null)
			return null;
		if (program == null)
			throw "Neko exact static call requires its typed program";
		final selected = program.requireFunction(call.owner, call.declaration);
		final declaration = selected.body.getDeclaration();
		if (!HxFunctionDecl.getIsStatic(declaration) || HxFunctionDecl.getName(declaration) != call.method)
			throw "Neko exact static call conflicts with declaration " + call.declaration;
		return new NekoExactStaticCallPlan(selected, call);
	}
}
