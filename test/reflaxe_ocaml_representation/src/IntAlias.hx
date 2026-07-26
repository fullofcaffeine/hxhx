/**
	A named primitive alias used to prove that exact `Null<Int>` admission does
	not silently widen to `Null<IntAlias>`.
**/
typedef IntAlias = Int;
