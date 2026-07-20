package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type.TypedExpr;

/**
	Defines the exact source shapes admitted to the new place-lowering path.

	Keeping this policy shared by input preservation and semantic planning means
	an expression cannot be hidden from Reflaxe's generic rewrite unless the target
	has a complete typed plan and emitter for it.
**/
class OcamlPlaceInputPolicy {
	static function isExactInt(type:Type):Bool {
		return OcamlRepresentationRegistry.isExactInt(type);
	}

	/** Recognizes only a direct nominal `Array<Int>` carrier. */
	static function isExactIntArray(type:Type):Bool {
		return switch (type) {
			case TInst(classRef, [elementType]): final classType = classRef.get(); classType.pack.length == 0 && classType.name == "Array" && isExactInt(elementType);
			case _:
				false;
		}
	}

	/** Recognizes an exact `Int` element place on a direct nominal `Array<Int>`. */
	static function admitsExactIntArrayElementPlace(left:TypedExpr):Bool {
		if (!isExactInt(left.t))
			return false;
		return switch (left.expr) {
			case TArray(receiver, index): isExactIntArray(receiver.t) && isExactInt(index.t);
			case _: false;
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

	/** Admits a directly writable, non-extern `Int` static backed by an OCaml ref. */
	static function admitsExactIntStaticFieldPlace(expression:TypedExpr):Bool {
		if (!isExactInt(expression.t))
			return false;
		return switch (expression.expr) {
			case TField(_, FStatic(classRef, fieldRef)): final classType = classRef.get(); final field = fieldRef.get(); final directlyWritable = switch (field.kind) {
					case FVar(_, AccNormal): !field.isFinal;
					case _: false;
				} directlyWritable && !classType.isExtern && !classType.isInterface && isExactInt(field.type);
			case _:
				false;
		}
	}

	/** Admits only static cells whose mutable OCaml declaration is already guaranteed. */
	static function admitsVisibleExactIntStaticFieldPlace(expression:TypedExpr, currentModuleId:Null<String>, currentTypeName:Null<String>):Bool {
		if (!admitsExactIntStaticFieldPlace(expression) || currentModuleId == null || currentTypeName == null)
			return false;
		return switch (expression.expr) {
			case TField(_, FStatic(classRef, _)): final target = classRef.get(); target.module != currentModuleId || target.name == currentTypeName;
			case _: false;
		}
	}

	/** Admits ordinary `Int` fields with an exact `Int` RHS for simple assignment. */
	public static function admitsSimpleInstanceField(left:TypedExpr, right:TypedExpr):Bool {
		return admitsExactIntInstanceFieldPlace(left) && isExactInt(right.t);
	}

	/**
		Admits mutable static `Int` ref cells whose declaration is already visible.

		A different type in the same Haxe module needs a program-level two-phase
		static declaration plan. That broader shape remains on the legacy path until
		its declaration-order owner lands.
	**/
	public static function admitsSimpleStaticField(left:TypedExpr, right:TypedExpr, currentModuleId:Null<String>, currentTypeName:Null<String>):Bool {
		return admitsVisibleExactIntStaticFieldPlace(left, currentModuleId, currentTypeName) && isExactInt(right.t);
	}

	/** Admits exact primitive-Int `+=` on an already-visible mutable static. */
	public static function admitsCompoundIntAddStaticField(operation:Binop, left:TypedExpr, right:TypedExpr, currentModuleId:Null<String>,
			currentTypeName:Null<String>):Bool {
		return operation == OpAdd && admitsVisibleExactIntStaticFieldPlace(left, currentModuleId, currentTypeName) && isExactInt(right.t);
	}

	/** Admits primitive-Int increment/decrement on an already-visible static. */
	public static function admitsIntUpdateStaticField(operation:Unop, operand:TypedExpr, currentModuleId:Null<String>, currentTypeName:Null<String>):Bool {
		return (operation == OpIncrement || operation == OpDecrement)
			&& admitsVisibleExactIntStaticFieldPlace(operand, currentModuleId, currentTypeName);
	}

	/** Admits exact `Array<Int>` element assignment with an exact `Int` index and RHS. */
	public static function admitsSimpleArrayElement(left:TypedExpr, right:TypedExpr):Bool {
		return admitsExactIntArrayElementPlace(left) && isExactInt(right.t);
	}

	/** Admits only exact primitive-Int `+=` on direct nominal `Array<Int>`. */
	public static function admitsCompoundIntAddArrayElement(operation:Binop, left:TypedExpr, right:TypedExpr):Bool {
		return operation == OpAdd && admitsExactIntArrayElementPlace(left) && isExactInt(right.t);
	}

	/** Admits both fixities of ordinary `Int` array-element increment/decrement. */
	public static function admitsIntUpdateArrayElement(operation:Unop, operand:TypedExpr):Bool {
		return (operation == OpIncrement || operation == OpDecrement) && admitsExactIntArrayElementPlace(operand);
	}

	/** Admits ordinary `Int` fields with an exact `Int` RHS for `+=`. */
	public static function admitsCompoundIntAddInstanceField(operation:Binop, left:TypedExpr, right:TypedExpr):Bool {
		return operation == OpAdd && admitsExactIntInstanceFieldPlace(left) && isExactInt(right.t);
	}

	/** Admits both fixities of ordinary `Int` instance-field increment/decrement. */
	public static function admitsIntUpdateInstanceField(operation:Unop, operand:TypedExpr):Bool {
		return (operation == OpIncrement || operation == OpDecrement) && admitsExactIntInstanceFieldPlace(operand);
	}

	/** Applies the complete first-slice admission policy to one typed operation. */
	public static function admitsExpression(expression:TypedExpr, currentModuleId:Null<String>, currentTypeName:Null<String>):Bool {
		return switch (expression.expr) {
			case TBinop(OpAssign, left, right): admitsSimpleInstanceField(left,
					right) || admitsSimpleStaticField(left, right, currentModuleId, currentTypeName) || admitsSimpleArrayElement(left, right);
			case TBinop(OpAssignOp(operation), left, right): admitsCompoundIntAddInstanceField(operation, left,
					right) || admitsCompoundIntAddStaticField(operation, left, right, currentModuleId,
					currentTypeName) || admitsCompoundIntAddArrayElement(operation, left, right);
			case TUnop(operation, _, operand): admitsIntUpdateInstanceField(operation,
					operand) || admitsIntUpdateStaticField(operation, operand, currentModuleId,
					currentTypeName) || admitsIntUpdateArrayElement(operation, operand);
			case _:
				false;
		}
	}
}
#end
