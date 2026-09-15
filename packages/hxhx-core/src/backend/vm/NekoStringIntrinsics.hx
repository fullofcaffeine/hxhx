package backend.vm;

/**
	Lowers the explicit Neko primitive boundary for native string creation, slicing, and byte reads.

	This target represents Haxe strings with native Neko strings. Core String
	construction therefore uses the native conversion primitive; it must not
	allocate the generic object used for an unknown constructor. Primitive calls
	keep their source argument order and native bounds failures. Only the fixed
	compiler primitive names below can select emitted syntax.

	The class exposes static helpers because bootstrap helper discovery currently
	indexes functions through class declarations.
**/
class NekoStringIntrinsics {
	/** Only the canonical core String type uses native construction, never a qualified namesake. */
	public static function ownsConstructor(typePath:String):Bool
		return typePath == "String";

	/** Ordinary calls return null; a selected intrinsic must have its exact arity. */
	public static function renderCall(callee:HxExpr, arguments:Array<String>):Null<String> {
		return switch (callee) {
			case EIdent("__dollar__string"): renderPrimitive("$string", 1, arguments);
			case EIdent("__dollar__ssub"): renderPrimitive("$ssub", 3, arguments);
			case EIdent("__dollar__sget"): renderPrimitive("$sget", 2, arguments);
			case _: null;
		};
	}

	/** Core String construction consumes the native value without an object wrapper. */
	public static function renderConstructor(arguments:Array<String>):String {
		return renderPrimitive("$string", 1, arguments);
	}

	static function renderPrimitive(symbol:String, arity:Int, arguments:Array<String>):String {
		if (arguments.length != arity)
			throw "Neko string intrinsic " + symbol + " requires " + arity + (arity == 1 ? " argument" : " arguments");
		return symbol + "(" + arguments.join(", ") + ")";
	}
}
