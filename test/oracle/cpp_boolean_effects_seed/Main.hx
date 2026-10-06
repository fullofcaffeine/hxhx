/** Both logical operators must skip or execute each right operand exactly once. */
class Main {
	static function main():Void {
		var effects = 0;
		final yes = true;
		final no = false;
		final skippedAnd = no && ++effects > 0;
		final skippedOr = yes || ++effects > 0;
		if (effects != 0)
			throw "short-circuit operands ran";
		final takenAnd = yes && ++effects > 0;
		final takenOr = no || ++effects > 0;
		if (effects != 2)
			throw "required operands did not run exactly once";
		if (skippedAnd || !skippedOr || !takenAnd || !takenOr)
			throw "logical result changed";
		if (!(yes && (no || yes)))
			throw "nested logical result changed";
	}
}
