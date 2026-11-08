/**
	Type an operator on an abstract that declares no matching `@:op`, through the
	abstract's primitive `to` types, as Haxe 4.3.7 does.

	The rule depends on the operator. Operands are checked left to right.

	- `- * / %`: each operand must be Int, Float, Dynamic, or an abstract with `to Int`.
	  The first other operand fails with `X should be Int`, so `m * 2.0` on an
	  `abstract M(Float) to Float` fails with `M should be Int`. The result is Float
	  when a Float or Dynamic operand is involved, and always for `/`; otherwise Int.
	- `& | ^ << >> >>>`: each operand must be Int, Dynamic, or an abstract with `to Int`.
	  The result is Int.
	- `+`: with a String the result is String, and with Dynamic it is Dynamic. Bool or a
	  second abstract fails with `Cannot add A and B`. With Int the abstract needs
	  `to Int` (`A should be Int`). With Float it needs `to Int` or `to Float`
	  (`A should be Float`), and the result is Float.
	- Unary `-` and `~`: the abstract needs `to Int`; the result is Int.

	A core type such as cpp's `Single` has no underlying type and counts as a Float
	operand of its own, except for bitwise operators, which it fails.

	The rule applies when at least one operand is such an abstract and the other is a
	primitive, Dynamic, or such an abstract. Any other shape returns null and stays with
	the declared-operator rules.

	A compound assignment uses the rule only for an abstract value, as in `i |= FA`. An
	abstract place would also need its result stored back through `from`, which shared
	lowering does not do yet (haxe_ocaml-efodd), so such places keep the
	declared-operator rules.
**/
typedef TyAbstractPrimitiveResult = {
	final failure:Null<String>;
	final result:Null<TyType>;
};

private enum TyOperandKind {
	IntValue;
	FloatValue;
	DynamicValue;
	StringValue;
	BoolValue;

	/** An abstract with `to Int`. **/
	IntAbstract;

	/** A core type such as `Single`, which has a primitive Float `to` type and no underlying type. **/
	CoreFloatAbstract;

	/** An abstract with `to Float` but no `to Int`. **/
	FloatAbstract;

	/** An abstract whose only primitive `to` types are neither Int nor Float. **/
	OtherAbstract;
}

private function abstractInfo(index:Null<TyperIndex>, type:TyType):Null<TyAbstractInfo> {
	if (index == null || type == null)
		return null;
	final identity = type.unwrapNull().getNominalIdentity();
	final info = identity == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
	return info == null || info.getTypeParameterIds().length != 0 ? null : info;
}

private function primitiveTargets(index:Null<TyperIndex>, type:TyType):Array<TyType> {
	final info = abstractInfo(index, type);
	return info == null ? [] : info.getImplicitToTypes().filter(target -> target.isPrimitive() && !target.isVoid());
}

/**
	The primitive `to` type an operator uses, or null when there is none. Int wins when an
	abstract declares several, because every operator rule accepts it, whatever the order
	in which the `to` types were written.
**/
function view(index:Null<TyperIndex>, type:TyType):Null<TyType> {
	final targets = primitiveTargets(index, type);
	for (target in targets)
		if (target.getDisplay() == "Int")
			return target;
	return targets.length == 0 ? null : targets[0];
}

private function kindOf(index:Null<TyperIndex>, type:TyType):Null<TyOperandKind> {
	final value = type.unwrapNull();
	if (value.isDynamic())
		return DynamicValue;
	final targets = primitiveTargets(index, type);
	if (targets.length != 0) {
		final names = targets.map(target -> target.getDisplay());
		if (names.indexOf("Int") >= 0)
			return IntAbstract;
		if (names.indexOf("Float") < 0)
			return OtherAbstract;
		return abstractInfo(index, type).getUnderlyingType().isUnknown() ? CoreFloatAbstract : FloatAbstract;
	}
	if (!value.isPrimitive())
		return null;
	return switch value.getDisplay() {
		case "Int": IntValue;
		case "Float": FloatValue;
		case "String": StringValue;
		case "Bool": BoolValue;
		case _: null;
	};
}

private function isAbstractKind(kind:TyOperandKind):Bool {
	return switch kind {
		case IntAbstract | CoreFloatAbstract | FloatAbstract | OtherAbstract: true;
		case _: false;
	};
}

private function failure(message:String):TyAbstractPrimitiveResult
	return {failure: message, result: null};

private function success(name:String):TyAbstractPrimitiveResult
	return {failure: null, result: TyType.fromHintText(name)};

/** Type `left op right` through primitive `to` types, or null when that rule does not apply. */
function operation(index:Null<TyperIndex>, op:String, left:TyType, right:TyType):Null<TyAbstractPrimitiveResult> {
	if (left == null || right == null)
		return null;
	final leftKind = kindOf(index, left);
	final rightKind = kindOf(index, right);
	if (leftKind == null || rightKind == null || (!isAbstractKind(leftKind) && !isAbstractKind(rightKind)))
		return null;
	final shown = [display(left, index), display(right, index)];
	final kinds = [leftKind, rightKind];
	return switch op {
		case "+": addition(kinds, shown);
		case "-" | "*" | "/" | "%": arithmetic(op, kinds, shown);
		case "&" | "|" | "^" | "<<" | ">>" | ">>>": bitwise(kinds, shown);
		case _: null;
	};
}

private function addition(kinds:Array<TyOperandKind>, shown:Array<String>):TyAbstractPrimitiveResult {
	final abstractSide = isAbstractKind(kinds[0]) ? 0 : 1;
	final otherSide = 1 - abstractSide;
	final other = kinds[otherSide];
	if (other.match(StringValue))
		return success("String");
	if (other.match(DynamicValue))
		return success("Dynamic");
	if (other.match(BoolValue) || isAbstractKind(other))
		return failure("Cannot add " + shown[0] + " and " + shown[1]);
	final subject = kinds[abstractSide];
	if (other.match(IntValue)) {
		if (subject.match(CoreFloatAbstract))
			return success("Float");
		return subject.match(IntAbstract) ? success("Int") : failure(shown[abstractSide] + " should be Int");
	}
	return subject.match(OtherAbstract) ? failure(shown[abstractSide] + " should be Float") : success("Float");
}

private function arithmetic(op:String, kinds:Array<TyOperandKind>, shown:Array<String>):TyAbstractPrimitiveResult {
	var floating = op == "/";
	for (side in 0...2)
		switch kinds[side] {
			case IntValue | IntAbstract:
			case FloatValue | DynamicValue | CoreFloatAbstract:
				floating = true;
			case _:
				return failure(shown[side] + " should be Int");
		}
	return success(floating ? "Float" : "Int");
}

private function bitwise(kinds:Array<TyOperandKind>, shown:Array<String>):TyAbstractPrimitiveResult {
	for (side in 0...2)
		switch kinds[side] {
			case IntValue | IntAbstract | DynamicValue:
			case _:
				return failure(shown[side] + " should be Int");
		}
	return success("Int");
}

/** Type unary `-` or `~` on such an abstract, or null when the operand is not one. */
function unary(index:Null<TyperIndex>, operand:TyType):Null<TyAbstractPrimitiveResult> {
	final kind = kindOf(index, operand);
	if (kind == null || !isAbstractKind(kind))
		return null;
	return kind.match(IntAbstract) ? success("Int") : failure(display(operand, index) + " should be Int");
}

/** Upstream prints an abstract by package path and name, without its declaring module. */
private function display(type:TyType, index:Null<TyperIndex>):String {
	final identity = type.unwrapNull().getNominalIdentity();
	final owner = identity == null || index == null ? null : index.getByFullName(identity.getCanonicalName());
	if (owner == null)
		return type.unwrapNull().getDisplay();
	final module = owner.getModulePath();
	final dot = module.lastIndexOf(".");
	return (dot < 0 ? "" : module.substr(0, dot + 1)) + owner.getShortName();
}
