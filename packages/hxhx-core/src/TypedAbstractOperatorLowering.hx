/**
	Seals every currently supported abstract operator before backend dispatch.

	Unary lowering runs first so binary helper bodies already contain explicit
	unary calls and mutation schedules. Binary lowering then resolves exact calls,
	commutative order, and compound places. Required inline lowering then expands
	static extern bodies and abstract methods that write directly to caller storage. Keeping this orchestration tiny avoids
	turning either semantic pass into a compiler-wide target IR.
**/
class TypedAbstractOperatorLowering {
	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex, filePath:String):Array<TypedClass> {
		final unary = TypedAbstractUnaryLowering.lowerClasses(classes, index, filePath);
		final receivers = TypedRequiredInlineLowering.lowerClasses(TypedAbstractBinaryLowering.lowerClasses(unary, index, filePath), index);
		return TypedPropertyLowering.lowerClasses(receivers, index, filePath);
	}

	public static function lowerModules(modules:Array<TypedModule>, index:TyperIndex):Array<TypedModule> {
		final unary = TypedAbstractUnaryLowering.lowerModules(modules, index);
		final receivers = TypedRequiredInlineLowering.lowerModules(TypedAbstractBinaryLowering.lowerModules(unary, index), index);
		return TypedPropertyLowering.lowerModules(receivers, index);
	}
}
