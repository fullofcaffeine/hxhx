/**
	Seals every currently supported abstract operator before backend dispatch.

	Unary lowering runs first so binary helper bodies already contain explicit
	unary calls and mutation schedules. Binary lowering then resolves exact calls,
	commutative order, and compound places. Keeping this orchestration tiny avoids
	turning either semantic pass into a compiler-wide target IR.
**/
class TypedAbstractOperatorLowering {
	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex, filePath:String):Array<TypedClass> {
		final unary = TypedAbstractUnaryLowering.lowerClasses(classes, index, filePath);
		return TypedAbstractBinaryLowering.lowerClasses(unary, index, filePath);
	}

	public static function lowerModules(modules:Array<TypedModule>, index:TyperIndex):Array<TypedModule> {
		final unary = TypedAbstractUnaryLowering.lowerModules(modules, index);
		return TypedAbstractBinaryLowering.lowerModules(unary, index);
	}
}
