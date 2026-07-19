package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
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

	/**
		Accepts a direct record-backed receiver while keeping inherited field
		declaration identity separate from the receiver representation.
	**/
	static function admitsExactIntInstanceFieldPlace(expression:TypedExpr):Bool {
		if (!isExactInt(expression.t))
			return false;
		return switch (expression.expr) {
			case TField(receiver, FInstance(classRef, _, fieldRef)): final classType = classRef.get(); final field = fieldRef.get(); final ordinaryField = switch (field.kind) {
					case FVar(_, _): true;
					case _: false;
				} final receiverIsRecordClass = switch (receiver.t) {
					case TInst(receiverClassRef, _): final receiverClass = receiverClassRef.get(); !receiverClass.isExtern && !receiverClass.isInterface;
					case _: false;
				} final isArrayLength = classType.pack.length == 0 && classType.name == "Array" && field.name == "length"; ordinaryField && receiverIsRecordClass && !classType.isExtern && !classType.isInterface && !isArrayLength;
			case _:
				false;
		}
	}

	/** Admits ordinary `Int` fields with an exact `Int` RHS for simple assignment. */
	public static function admitsSimpleInstanceField(left:TypedExpr, right:TypedExpr):Bool {
		return admitsExactIntInstanceFieldPlace(left) && isExactInt(right.t);
	}

	/** Admits ordinary `Int` fields with an exact `Int` RHS for `+=`. */
	public static function admitsCompoundIntAddInstanceField(operation:Binop, left:TypedExpr, right:TypedExpr):Bool {
		return operation == OpAdd && admitsExactIntInstanceFieldPlace(left) && isExactInt(right.t);
	}

	/** Admits both fixities of ordinary `Int` instance-field increment/decrement. */
	public static function admitsIntUpdateInstanceField(operation:Unop, operand:TypedExpr):Bool {
		return (operation == OpIncrement || operation == OpDecrement) && admitsExactIntInstanceFieldPlace(operand);
	}
}
#end
