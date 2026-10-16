/**
	Seals every currently supported abstract operator before backend dispatch.

	Unary lowering runs first so binary helper bodies already contain explicit
	unary calls and mutation schedules. Binary lowering then resolves exact calls,
	commutative order, and compound places. Property selection exposes accessor
	calls before required inline lowering expands extern inline bodies and abstract
	methods that write directly to caller storage. Keeping this orchestration tiny
	avoids turning either semantic pass into a compiler-wide target IR.
**/
class TypedAbstractOperatorLowering {
	/** A target can retain exact native calls; all other required bodies keep shared expansion. */
	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex, filePath:String,
			?retainNativeCall:TyDeclarationInfo->Bool):Array<TypedClass> {
		final unary = TypedAbstractUnaryLowering.lowerClasses(classes, index, filePath);
		final properties = TypedPropertyLowering.lowerClasses(TypedAbstractBinaryLowering.lowerClasses(unary, index, filePath), index, filePath);
		return TypedRequiredInlineLowering.lowerClasses(properties, index, retainNativeCall);
	}

	/** Apply the same target call contract after the complete dependency closure is typed. */
	public static function lowerModules(modules:Array<TypedModule>, index:TyperIndex, ?retainNativeCall:TyDeclarationInfo->Bool):Array<TypedModule> {
		final unary = TypedAbstractUnaryLowering.lowerModules(modules, index);
		final properties = TypedPropertyLowering.lowerModules(TypedAbstractBinaryLowering.lowerModules(unary, index), index);
		return TypedRequiredInlineLowering.lowerModules(properties, index, retainNativeCall);
	}
}
