/**
	The parameter facts needed to align a source call, independently of a target ABI.

	Fixed parameters exclude a trailing rest parameter. A receiver can already be
	applied to the callee; it remains distinct from supplied source arguments.
	Type compatibility is supplied by the caller and never recovered from names.
 */
typedef TyCallParameterLayout = {
	final fixed:Int;
	final needsReceiver:Bool;
	final paramNames:Array<String>;
	final paramFillable:Array<Bool>;
};
