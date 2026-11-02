package backend.ocaml;

/**
	Join two already rendered String operands with OCaml's `^`, keeping Haxe's
	left-to-right evaluation order.

	Why
	- Haxe evaluates `a + b` left to right. OCaml evaluates the arguments of
	  `(^) a b` right to left, so `"x" + f() + g()` called `g` before `f` and
	  `"t=" + (n = 5) + " " + n` read `n` before the assignment.

	What
	- When either operand is stable, meaning that evaluating it has no effect and its
	  value cannot change (a literal, or a read of an immutable local), the
	  order is not observable and the plain `(left ^ right)` form is kept. Most
	  concatenations have a literal on one side, so their generated text stays
	  unchanged.
	- Otherwise the left operand is bound first, then the right operand, and
	  the two names are joined.
	- Without a local naming owner (no current function), the plain form is
	  kept, as before.
**/
function render(left:String, right:String, leftStable:Bool, rightStable:Bool, names:Null<Stage3OcamlLocalNames>):String {
	if (leftStable || rightStable || names == null)
		return "((" + left + ") ^ (" + right + "))";
	final leftName = names.internalName("__hx_concat_left");
	final rightName = names.internalName("__hx_concat_right");
	return "(let "
		+ leftName
		+ " = ("
		+ left
		+ ") in let "
		+ rightName
		+ " = ("
		+ right
		+ ") in "
		+ leftName
		+ " ^ "
		+ rightName
		+ ")";
}
