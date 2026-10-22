/**
	Project a checked call into positional source arguments.

	An omitted parameter needs null only when another operand follows it. Keep
	trailing omissions absent so targets can preserve argument-count behavior.
	Reuse operand expressions without copying, reordering, or packing rest values;
	targets still own rest representation and spread emission.
**/
function arguments(binding:TyCallArgumentBinding, operands:Array<HxExpr>):Array<HxExpr>
	return TyCallArgumentProjection.project(binding.getSlots(), operands, HxExpr.ENull, binding.getOperandTypes().length);

/** Keep projected type facts in exactly the same order as projected source operands. */
function types(binding:TyCallArgumentBinding):Array<TyType>
	return TyCallArgumentProjection.project(binding.getSlots(), binding.getOperandTypes(), TyType.fromHintText("Null"), binding.getOperandTypes().length);
