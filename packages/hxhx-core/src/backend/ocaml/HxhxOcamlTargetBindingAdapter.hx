package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetBindingFact;
import reflaxe.ocaml.target.OcamlTargetBindingFact.OcamlTargetBindingRole;

/** Copies a native source binding without exposing its internal local key. **/
class HxhxOcamlTargetBindingAdapter {
	public static function fromBinding(ownerIdentity:String, binding:TyLocalBinding, declarationPath:String):OcamlTargetBindingFact {
		if (binding == null)
			throw "native OCaml binding adapter requires a typed binding";
		final identity = binding.getIdentity();
		if (identity.isCompilerTemporary())
			throw "native OCaml binding adapter does not admit compiler temporaries in source-binding revision 1";
		if (identity.getDeclarationKind() != binding.getKind())
			throw "native OCaml binding adapter received conflicting declaration roles";
		return new OcamlTargetBindingFact(ownerIdentity, declarationPath, role(identity.getDeclarationKind()), binding.getSourceName(),
			binding.getType().getCanonicalDisplay());
	}

	static function role(kind:TyLocalDeclarationKind):OcamlTargetBindingRole {
		return switch (kind) {
			case Parameter: Parameter;
			case Variable: Variable;
			case LoopVariable: LoopVariable;
			case CatchVariable: CatchVariable;
			case PatternVariable: PatternVariable;
			case LambdaParameter: LambdaParameter;
			case ComprehensionVariable: ComprehensionVariable;
			case CompilerTemporary: throw "native OCaml source-binding adapter received a compiler temporary";
		};
	}
}
