/**
	Project a checked call into positional source arguments.

	An omitted parameter needs null only when another operand follows it. Keep
	trailing omissions absent so targets can preserve argument-count behavior.
	Reuse operand expressions without copying, reordering, or packing rest values;
	targets still own rest representation and spread emission.
**/
function arguments(binding:TyCallArgumentBinding, operands:Array<HxExpr>):Array<HxExpr>
	return project(binding, operands, HxExpr.ENull);

/** Keep projected type facts in exactly the same order as projected source operands. */
function types(binding:TyCallArgumentBinding):Array<TyType>
	return project(binding, binding.getOperandTypes(), TyType.fromHintText("Null"));

private function project<T>(binding:TyCallArgumentBinding, operands:Array<T>, omittedValue:T):Array<T> {
	if (operands.length != binding.getOperandTypes().length)
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
	for (slot in binding.getSlots())
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
