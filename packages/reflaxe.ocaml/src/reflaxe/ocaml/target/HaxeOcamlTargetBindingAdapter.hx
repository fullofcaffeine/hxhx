package reflaxe.ocaml.target;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TVar;
import haxe.macro.TypeTools;
import reflaxe.ocaml.target.OcamlTargetBindingFact.OcamlTargetBindingRole;
#end

/**
	Copies an original typed-Haxe source binding into target-owned facts.

	Call this adapter before target preprocessors can introduce temporary locals.
	The caller supplies the target-owned structural path selected while copying the
	original typed expression. No `TVar.id` or Reflaxe-internal lexical key crosses
	the boundary.
**/
class HaxeOcamlTargetBindingAdapter {
	#if (macro || reflaxe_runtime)
	public static function fromSourceLocalBeforePreprocessing(ownerIdentity:String, declarationPath:String, role:OcamlTargetBindingRole,
			local:TVar):OcamlTargetBindingFact {
		if (local == null)
			throw "standalone OCaml binding adapter requires a typed source local";
		return new OcamlTargetBindingFact(ownerIdentity, declarationPath, role, local.name, TypeTools.toString(local.t));
	}
	#end
}
