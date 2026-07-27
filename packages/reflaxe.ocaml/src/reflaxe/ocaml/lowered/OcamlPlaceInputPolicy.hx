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

	static function isExactBool(type:Type):Bool {
		return OcamlRepresentationRegistry.isExactBool(type);
	}

	static function isExactString(type:Type):Bool {
		return OcamlRepresentationRegistry.isExactString(type);
	}

	static function isSameDirectCarrier(left:Type, right:Type):Bool {
		return (isExactInt(left) && isExactInt(right))
			|| (isExactBool(left) && isExactBool(right))
			|| (isExactString(left) && isExactString(right));
	}

	static function isAdmittedSimpleValue(left:Type, right:TypedExpr):Bool {
		if ((isExactInt(left) && isExactInt(right.t)) || (isExactBool(left) && isExactBool(right.t)))
			return true;
		if (!isExactString(left) || !isExactString(right.t))
			return false;
		return switch (right.expr) {
			case TConst(TString(_)): true;
			case _: false;
		}
	}

	/** Recognizes only a direct nominal `Array<Int>` carrier. */
	static function isExactIntArray(type:Type):Bool {
		return OcamlRepresentationRegistry.isExactArrayInt(type);
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
	static function admitsDirectPrimitiveInstanceFieldPlace(expression:TypedExpr):Bool {
		if (!isExactInt(expression.t) && !isExactBool(expression.t) && !isExactString(expression.t))
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

	static function admitsExactIntInstanceFieldPlace(expression:TypedExpr):Bool {
		return isExactInt(expression.t) && admitsDirectPrimitiveInstanceFieldPlace(expression);
	}

	/** Admits a directly writable, non-extern primitive static backed by a ref. */
	static function admitsDirectPrimitiveStaticFieldPlace(expression:TypedExpr):Bool {
		if (!isExactInt(expression.t) && !isExactBool(expression.t) && !isExactString(expression.t))
			return false;
		return switch (expression.expr) {
			case TField(_, FStatic(classRef, fieldRef)): final classType = classRef.get(); final field = fieldRef.get(); final directlyWritable = switch (field.kind) {
					case FVar(_, AccNormal): !field.isFinal;
					case _: false;
				} directlyWritable && !classType.isExtern && !classType.isInterface && isSameDirectCarrier(expression.t, field.type);
			case _:
				false;
		}
	}

	static function admitsExactIntStaticFieldPlace(expression:TypedExpr):Bool {
		return isExactInt(expression.t) && admitsDirectPrimitiveStaticFieldPlace(expression);
	}

	/** Admits only direct primitive static cells with an already-visible declaration. */
	static function admitsVisibleDirectPrimitiveStaticFieldPlace(expression:TypedExpr, currentModuleId:Null<String>, currentTypeName:Null<String>,
			staticStorage:OcamlStaticStoragePlan):Bool {
		if (!admitsDirectPrimitiveStaticFieldPlace(expression) || currentModuleId == null || currentTypeName == null)
			return false;
		return switch (expression.expr) {
			case TField(_, FStatic(classRef, fieldRef)):
				final target = classRef.get();
				final field = fieldRef.get();
				staticStorage.isVisibleFrom(target.module, target.name, field.name, currentModuleId, currentTypeName);
			case _: false;
		}
	}

	/** Admits only visible exact-Int static cells for Int-only operator families. */
	static function admitsVisibleExactIntStaticFieldPlace(expression:TypedExpr, currentModuleId:Null<String>, currentTypeName:Null<String>,
			staticStorage:OcamlStaticStoragePlan):Bool {
		return admitsExactIntStaticFieldPlace(expression)
			&& admitsVisibleDirectPrimitiveStaticFieldPlace(expression, currentModuleId, currentTypeName, staticStorage);
	}

	/** Admits direct primitive fields with a matching exact RHS. */
	public static function admitsSimpleInstanceField(left:TypedExpr, right:TypedExpr):Bool {
		return admitsDirectPrimitiveInstanceFieldPlace(left) && isAdmittedSimpleValue(left.t, right);
	}

	/**
		Admits mutable direct primitive ref cells whose declaration is visible.

		For a different type in the same Haxe module, visibility comes from the sealed
		program-level storage plan: the cell is either declared in an earlier type
		fragment or in a prelude before the referencing value bindings.
	**/
	public static function admitsSimpleStaticField(left:TypedExpr, right:TypedExpr, currentModuleId:Null<String>, currentTypeName:Null<String>,
			staticStorage:OcamlStaticStoragePlan):Bool {
		return admitsVisibleDirectPrimitiveStaticFieldPlace(left, currentModuleId, currentTypeName, staticStorage)
			&& isAdmittedSimpleValue(left.t, right);
	}

	/** Admits exact primitive-Int `+=` on an already-visible mutable static. */
	public static function admitsCompoundIntAddStaticField(operation:Binop, left:TypedExpr, right:TypedExpr, currentModuleId:Null<String>,
			currentTypeName:Null<String>, staticStorage:OcamlStaticStoragePlan):Bool {
		return operation == OpAdd
			&& admitsVisibleExactIntStaticFieldPlace(left, currentModuleId, currentTypeName, staticStorage)
			&& isExactInt(right.t);
	}

	/** Admits primitive-Int increment/decrement on an already-visible static. */
	public static function admitsIntUpdateStaticField(operation:Unop, operand:TypedExpr, currentModuleId:Null<String>, currentTypeName:Null<String>,
			staticStorage:OcamlStaticStoragePlan):Bool {
		return (operation == OpIncrement || operation == OpDecrement)
			&& admitsVisibleExactIntStaticFieldPlace(operand, currentModuleId, currentTypeName, staticStorage);
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
	public static function admitsExpression(expression:TypedExpr, currentModuleId:Null<String>, currentTypeName:Null<String>,
			staticStorage:OcamlStaticStoragePlan):Bool {
		return switch (expression.expr) {
			case TBinop(OpAssign, left, right): admitsSimpleInstanceField(left,
					right) || admitsSimpleStaticField(left, right, currentModuleId, currentTypeName, staticStorage) || admitsSimpleArrayElement(left, right);
			case TBinop(OpAssignOp(operation), left, right): admitsCompoundIntAddInstanceField(operation, left,
					right) || admitsCompoundIntAddStaticField(operation, left, right, currentModuleId, currentTypeName,
					staticStorage) || admitsCompoundIntAddArrayElement(operation, left, right);
			case TUnop(operation, _, operand): admitsIntUpdateInstanceField(operation,
					operand) || admitsIntUpdateStaticField(operation, operand, currentModuleId, currentTypeName,
					staticStorage) || admitsIntUpdateArrayElement(operation, operand);
			case _:
				false;
		}
	}
}
#end
