/**
	Project already-checked parameter slots while keeping operand values opaque.
	Only omissions before a later operand need placeholders. Trailing omissions
	stay absent, and rest spreads remain one operand for the target to expand.
	Typing owns slot validation and supplies the original operand count. This
	module depends only on positional data, so it cannot pull typing state into
	the generic helper's native compilation unit.
 */
function project<T>(slots:Array<TyCallArgumentSlot>, operands:Array<T>, omittedValue:T, operandCount:Int):Array<T> {
	if (operands.length != operandCount)
		throw "call argument projection has a stale operand count";
	final result = new Array<T>();
	var omitted = 0;
	function supply(index:Int):Void {
		while (omitted > 0) {
			result.push(omittedValue);
			omitted--;
		}
		result.push(operands[index]);
	}
	for (slot in slots)
		switch (slot) {
			case Omitted:
				omitted++;
			case Supplied(index) | RestSpread(index):
				supply(index);
			case RestElements(indices):
				for (index in indices)
					supply(index);
		}
	return result;
}
