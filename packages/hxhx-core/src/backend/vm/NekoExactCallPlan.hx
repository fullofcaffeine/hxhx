package backend.vm;

import backend.vm.NekoTypedProgramProjection.NekoProjectedFunction;

/**
	Pairs an encoded exact instance call with its program-owned typed body.

	Reachability and rendering use the same selected declaration. Abstract methods
	receive their backing value explicitly; ordinary object methods keep runtime
	dispatch so an override can still run. The shared nominal kind owns this choice.
**/
class NekoExactCallPlan {
	public final selected:NekoProjectedFunction;
	public final receiver:HxExpr;

	final arguments:Array<HxExpr>;

	function new(selected:NekoProjectedFunction, call:TypedExactCallSource.TypedExactInstanceCall) {
		this.selected = selected;
		receiver = call.receiver;
		arguments = call.arguments.copy();
	}

	/** Returns source arguments in their already-selected evaluation order. */
	public function getArguments():Array<HxExpr>
		return arguments.copy();

	/** Only a semantic abstract declaration uses an explicit backing-value receiver. */
	public function usesAbstractReceiver():Bool {
		return switch (selected.nominalKind) {
			case AbstractValue(_): true;
			case ClassInstance, EnumValue: false;
		};
	}

	/** Ordinary calls return null; malformed reserved exact-call payloads fail. */
	public static function fromExpression(program:Null<NekoTypedProgramProjection>, expression:HxExpr):Null<NekoExactCallPlan> {
		final call = TypedExactCallSource.decodeInstance(expression);
		if (call == null) {
			switch (expression) {
				case ECall(EIdent(TypedExactCallSource.INSTANCE_INTRINSIC), _):
					throw "Neko exact instance call contains a malformed typed payload";
				case _:
					return null;
			}
		}
		if (call.owner.length == 0 || call.declaration.length == 0 || call.method.length == 0 || call.resultType.length == 0)
			throw "Neko exact instance call contains empty typed identities";
		if (program == null)
			throw "Neko exact instance call requires its typed program";
		final selected = program.requireFunction(call.owner, call.declaration);
		final declaration = selected.body.getDeclaration();
		if (HxFunctionDecl.getIsStatic(declaration) || HxFunctionDecl.getName(declaration) != call.method)
			throw "Neko exact instance call conflicts with declaration " + call.declaration;
		return new NekoExactCallPlan(selected, call);
	}
}
