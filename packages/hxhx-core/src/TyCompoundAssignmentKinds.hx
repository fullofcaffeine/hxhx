/**
	Check the numeric kinds of a compound assignment such as `x |= 1` or `x /= 2`.

	Upstream Haxe 4.3.7 types `place op= value` like `place = place op value`:

	- A bitwise operator (`&=`, `|=`, `^=`, `<<=`, `>>=`, `>>>=`) needs Int operands, so
	  a Float place or a Float value fails with `Float should be Int`, also for a
	  Dynamic place.
	- An arithmetic operator produces Float when either side is Float, and `/` always
	  produces Float. Storing that Float into an Int place fails with `Float should be
	  Int` (or `Float should be Null<Int>` for a nullable place).

	`primitive` handles Int and Float places directly. `abstractFailure` rewords the
	failure of an abstract place such as `haxe.Int32` or `UInt`, whose operator
	lookup has already failed, the way upstream reports it: `Float should be
	haxe.Int32` for arithmetic and `Float should be Int` for bitwise operators.
	Dynamic, unknown or non-numeric operands are left to the existing rules.
**/
function primitive(op:String, place:TyType, value:TyType):Null<String> {
	final left = place.unwrapNull();
	final right = value.unwrapNull();
	// A bitwise operator needs an Int value even for a Dynamic place: `d |= 1.5` fails.
	if (isBitwise(op) && isFloat(right) && left.isDynamic())
		return "Float should be Int";
	if (!isNumber(left) || !isNumber(right))
		return null;
	if (isBitwise(op))
		return isFloat(left) || isFloat(right) ? "Float should be Int" : null;
	final producesFloat = op == "/=" || isFloat(left) || isFloat(right);
	return producesFloat && !isFloat(left) ? "Float should be " + display(place) : null;
}

/** Reword a failed abstract operator lookup for a numeric value; null keeps the original error. */
function abstractFailure(op:String, place:TyType, value:TyType, index:Null<TyperIndex>):Null<String> {
	final right = value.unwrapNull();
	if (!isNumber(right))
		return null;
	if (isBitwise(op))
		return isFloat(right) ? "Float should be Int" : null;
	return op == "/=" || isFloat(right) ? "Float should be " + abstractDisplay(place, index) : null;
}

private function isBitwise(op:String):Bool
	return op == "&=" || op == "|=" || op == "^=" || op == "<<=" || op == ">>=" || op == ">>>=";

private function isNumber(type:TyType):Bool
	return type.isPrimitive() && (type.getDisplay() == "Int" || type.getDisplay() == "Float");

private function isFloat(type:TyType):Bool
	return type.isPrimitive() && type.getDisplay() == "Float";

private function display(type:TyType):String
	return type.isNullable() ? "Null<" + display(type.unwrapNull()) + ">" : type.getDisplay();

/** Upstream prints an abstract by package path and name, without its declaring module. */
private function abstractDisplay(type:TyType, index:Null<TyperIndex>):String {
	if (type.isNullable())
		return "Null<" + abstractDisplay(type.unwrapNull(), index) + ">";
	final identity = type.getNominalIdentity();
	final owner = identity == null || index == null ? null : index.getByFullName(identity.getCanonicalName());
	if (owner == null)
		return type.getDisplay();
	final module = owner.getModulePath();
	final dot = module.lastIndexOf(".");
	return (dot < 0 ? "" : module.substr(0, dot + 1)) + owner.getShortName();
}
