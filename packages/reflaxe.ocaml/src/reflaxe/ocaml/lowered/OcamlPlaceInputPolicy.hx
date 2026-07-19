package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;

/**
	Defines the exact source shapes admitted to the new place-lowering path.

	Keeping this policy shared by input preservation and semantic planning means
	an expression cannot be hidden from Reflaxe's generic rewrite unless the target
	has a complete typed plan and emitter for it.
**/
class OcamlPlaceInputPolicy {
	static function isExactInt(type:Type):Bool {
		var current = type;
		var following = true;
		var depth = 0;
		while (following && depth < 32) {
			depth += 1;
			current = switch (current) {
				case TLazy(resolve): resolve();
				case TMono(reference):
					final resolved = reference.get();
					if (resolved == null) {
						following = false;
						current;
					} else {
						resolved;
					}
				case TType(typeRef, parameters):
					final typedefType = typeRef.get();
					TypeTools.applyTypeParameters(typedefType.type, typedefType.params, parameters);
				case _:
					following = false;
					current;
			}
		}
		if (following)
			return false;
		return switch (current) {
			case TAbstract(abstractRef, _): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Int";
			case _:
				false;
		}
	}

	/** Admits ordinary `Int` fields with an exact `Int` RHS for the first slice. */
	public static function admitsSimpleInstanceField(left:TypedExpr, right:TypedExpr):Bool {
		if (!isExactInt(left.t) || !isExactInt(right.t))
			return false;
		return switch (left.expr) {
			case TField(_, FInstance(classRef, _, fieldRef)): final classType = classRef.get(); final field = fieldRef.get(); final ordinaryField = switch (field.kind) {
					case FVar(_, _): true;
					case _: false;
				} final isArrayLength = classType.pack.length == 0 && classType.name == "Array" && field.name == "length"; ordinaryField && !classType.isExtern && !classType.isInterface && !isArrayLength;
			case _:
				false;
		}
	}
}
#end
