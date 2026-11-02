package backend.ocaml;

/**
	Combine two already rendered operands of a binary operator while keeping
	Haxe's left-to-right evaluation order.

	Why
	- Haxe evaluates `a op b` left to right. Stage3 renders many operators as
	  one OCaml application, such as `(a ^ b)`, `(a /. b)` or `(a < b)`, and
	  OCaml evaluates application operands right to left. So
	  `"x" + f() + g()` called `g` before `f`, `side("I", 8) / side("J", 2)`
	  ran `side("J", 2)` first, and `"p " + Std.string(w++) + " " + Std.string(w)`
	  read `w` before the increment.

	What
	- An operand is stable when evaluating it has no effect and its value
	  cannot change: a literal, or a read of an immutable local. When either
	  operand is stable, the order cannot be observed, and `body` receives the
	  rendered operands directly. Most concatenations have a literal on one side,
	  so their generated text stays unchanged.
	- Otherwise the left operand is bound first, then the right operand, and
	  `body` receives the two names.
	- Without a local naming owner (no current function), `body` receives the
	  operands directly, as before.
**/
function apply(left:String, right:String, leftStable:Bool, rightStable:Bool, names:Null<Stage3OcamlLocalNames>, body:(String, String) -> String):String {
	if (leftStable || rightStable || names == null)
		return body(left, right);
	final leftName = names.internalName("__hx_ordered_left");
	final rightName = names.internalName("__hx_ordered_right");
	return "(let "
		+ leftName
		+ " = ("
		+ left
		+ ") in let "
		+ rightName
		+ " = ("
		+ right
		+ ") in "
		+ body(leftName, rightName)
		+ ")";
}

/** String concatenation with OCaml `^`, in Haxe evaluation order. */
function concat(left:String, right:String, leftStable:Bool, rightStable:Bool, names:Null<Stage3OcamlLocalNames>):String {
	return apply(left, right, leftStable, rightStable, names, (l, r) -> "((" + l + ") ^ (" + r + "))");
}
