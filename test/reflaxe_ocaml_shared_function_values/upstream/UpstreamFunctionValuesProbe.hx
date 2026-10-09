/** Establish the result contract independently with upstream Haxe before target adaptation. */
class UpstreamFunctionValuesProbe {
	static function main():Void {
		if (Main.choose(7, 9) != 7 || Main.choose(-3, 11) != -3)
			throw "function result did not preserve the first argument";
		if (!Main.logical(true) || Main.logical(false))
			throw "function result did not preserve its Boolean argument";
		if (Main.text("hé\x00z") != "hé\x00z")
			throw "function result did not preserve its String argument";
		if (Main.invoke(3, 5) != 3 || Main.invoke(-8, 3) != -8 || Main.scoped(8) != 8)
			throw "nested calls or shadowing changed a parameter value";
		Main.done();
		if (Main.branchReturn(true, 7, 9) != 7 || Main.branchReturn(false, 7, 9) != 9)
			throw "terminal conditional returns changed their results";
		if (Main.branch(true, 0, 9) != 0 || Main.branch(false, 0, 9) != 9)
			throw "conditional selected the wrong integer";
		if (Main.branchBool(true, false, true) || !Main.branchBool(false, false, true))
			throw "conditional selected the wrong Boolean";
		if (Main.branchText(true, "left", "right") != "left" || Main.branchText(false, "left", "right") != "right")
			throw "conditional selected the wrong String";
		if (Main.branchBlock(true, -7, 9) != -7 || Main.branchBlock(false, -7, 9) != 9)
			throw "conditional lost a branch-local value";
		if (Main.nestedBranch(true, true, 5) != 5
			|| Main.nestedBranch(true, false, 5) != 17
			|| Main.nestedBranch(false, true, 5) != 29
			|| Main.nestedBranch(false, false, 5) != 5)
			throw "nested conditional selected the wrong branch";
	}
}
