package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
#end
import reflaxe.ocaml.lowered.OcamlCallableOriginKind;

#if (macro || reflaxe_runtime)
/**
	Selects identity from typed syntax before a function plan selects storage.

	A call returning a function, a local read, and a field read are not new lambda
	evaluations. Their identity must come from their own producer/storage plans.
	In particular, a function type alone does not permit a fresh token or a raw
	closure identity. Metadata and parentheses preserve the underlying operation;
	casts and other expression forms need their own boundary evidence.

	The enclosing function plan owns source occurrence and body revision binding.
	This classifier neither caches typed objects nor grants a calling convention.
**/
function classify(expression:TypedExpr):Null<OcamlCallableOriginKind> {
	return switch (expression.expr) {
		case TParenthesis(inner), TMeta(_, inner): classify(inner);
		case TFunction(_): FreshLiteral;
		case TField({expr: TTypeExpr(TClassDecl(receiver))}, FStatic(owner, member)):
			final declaration = owner.get();
			final field = member.get();
			// Require the actual declaration receiver. Do not discard evaluation
			// of an arbitrary expression merely because its field is static.
			if (receiver.get().module != declaration.module
				|| receiver.get().name != declaration.name
				|| declaration.isExtern
				|| declaration.isInterface
				|| declaration.params.length != 0
				|| declaration.meta.has(":native")
				|| field.isExtern
				|| field.meta.has(":native")
				|| field.params.length != 0
				|| field.overloads.get().length != 0
				|| field.expr() == null) {
				null;
			} else switch ([declaration.kind, field.kind]) {
				case [KNormal, FMethod(MethNormal)]: StaticDeclaration(OcamlCallPlanner.calleeId(declaration, field));
				case _: null;
			}
		case _: null;
	};
}
#end
