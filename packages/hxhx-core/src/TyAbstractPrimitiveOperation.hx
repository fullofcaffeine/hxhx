/**
	Type an operator on an abstract that declares no matching `@:op`, through the
	abstract's `to` primitive, as Haxe 4.3.7 does.

	Upstream lets such an operator proceed when exactly one operand is an abstract with a
	primitive `to` type and the other operand is a primitive. The abstract must convert to
	the other operand's type, Int also widening to Float:

		enum abstract ET(Int) to Int { var T1 = 1; }
		T1 + 1;      // Int
		T1 * 1.5;    // Float
		abstract S(String) from String to String {}
		s + "b";     // String
		s + 1;       // error: S should be Int
		"n=" + int32;  // String: `+` with a String concatenates any value

	The result has the other operand's type (`/` always gives Float). A compound
	assignment uses the rule only for an abstract value, as in `i |= FA`. An abstract
	place would also need its result stored back through `from`, which shared lowering
	does not do yet (haxe_ocaml-efodd), so such places keep the declared-operator rules.

	Two abstract operands, or a non-primitive operand, are left to the declared-operator
	rules, which reject them as before.
**/
typedef TyAbstractPrimitiveResult = {
	final failure:Null<String>;
	final result:Null<TyType>;
};

/** The primitive `to` type of a non-generic abstract, or null. */
function view(index:Null<TyperIndex>, type:TyType):Null<TyType> {
	if (index == null || type == null)
		return null;
	final identity = type.unwrapNull().getNominalIdentity();
	final info = identity == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
	if (info == null || info.getTypeParameterIds().length != 0)
		return null;
	for (target in info.getImplicitToTypes())
		if (target.isPrimitive() && !target.isVoid())
			return target;
	return null;
}

/** Type `left op right` through one abstract's `to` primitive, or null when that rule does not apply. */
function operation(index:Null<TyperIndex>, op:String, left:TyType, right:TyType):Null<TyAbstractPrimitiveResult> {
	if (left == null || right == null)
		return null;
	final leftView = view(index, left);
	final rightView = view(index, right);
	if ((leftView == null) == (rightView == null))
		return null;
	final abstractType = leftView != null ? left : right;
	final primitive = leftView != null ? leftView : rightView;
	final other = (leftView != null ? right : left).unwrapNull();
	if (!isOperand(other))
		return null;
	// `+` with a String concatenates any value, as in `"n=" + int32`.
	if (op == "+" && other.getDisplay() == "String")
		return {failure: null, result: other};
	// Bitwise operators need Int on both sides: `s |= 1` on cpp's `Single` fails.
	if (isBitwise(op)) {
		if (primitive.getDisplay() != "Int")
			return {failure: display(abstractType, index) + " should be Int", result: null};
		return other.getDisplay() == "Int" ? {failure: null, result: other} : {failure: other.getDisplay() + " should be Int", result: null};
	}
	// A core type such as `Single` (no underlying type) is a number of its own, so an
	// Int operand widens to it; an ordinary abstract must convert to the other side.
	final core = isCoreType(index, abstractType);
	if (!fits(primitive, other) && !(core && fits(other, primitive)))
		return {failure: display(abstractType, index) + " should be " + other.getDisplay(), result: null};
	final floating = op == "/" || primitive.getDisplay() == "Float" || other.getDisplay() == "Float";
	return {failure: null, result: floating && isNumber(other) ? TyType.fromHintText("Float") : other};
}

private function isBitwise(op:String):Bool
	return op == "&" || op == "|" || op == "^" || op == "<<" || op == ">>" || op == ">>>";

private function isNumber(type:TyType):Bool
	return type.getDisplay() == "Int" || type.getDisplay() == "Float";

private function isCoreType(index:Null<TyperIndex>, type:TyType):Bool {
	final identity = type.unwrapNull().getNominalIdentity();
	final info = identity == null || index == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
	return info != null && info.getUnderlyingType().isUnknown();
}

private function isOperand(type:TyType):Bool {
	if (!type.isPrimitive())
		return false;
	final name = type.getDisplay();
	return name == "Int" || name == "Float" || name == "String" || name == "Bool";
}

/** Whether a value of `actual` primitive type can be used as `expected`: equal, or Int widening to Float. */
private function fits(actual:TyType, expected:TyType):Bool {
	final value = actual.unwrapNull();
	final target = expected.unwrapNull();
	return value.getSemanticKey() == target.getSemanticKey() || (value.getDisplay() == "Int" && target.getDisplay() == "Float");
}

/** Upstream prints an abstract by package path and name, without its declaring module. */
private function display(type:TyType, index:Null<TyperIndex>):String {
	final identity = type.unwrapNull().getNominalIdentity();
	final owner = identity == null || index == null ? null : index.getByFullName(identity.getCanonicalName());
	if (owner == null)
		return type.getDisplay();
	final module = owner.getModulePath();
	final dot = module.lastIndexOf(".");
	return (dot < 0 ? "" : module.substr(0, dot + 1)) + owner.getShortName();
}
