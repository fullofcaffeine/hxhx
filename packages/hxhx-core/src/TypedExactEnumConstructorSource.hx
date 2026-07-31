typedef TypedExactEnumConstructorCall = {
	final owner:String;
	final modulePath:String;
	final declaration:String;
	final constructor:String;
	final callee:HxExpr;
	final arguments:Array<HxExpr>;
};

/**
	Carry one already-selected enum constructor through the source-shaped adapter.

	The typer owns Haxe lookup and stores the stable declaration identity. Targets
	may translate that owner into their namespace and identifier syntax, but they
	must not search constructor names again. `EUnsupported` is used as a
	source-impossible structural marker so user Haxe code cannot forge this
	compiler-owned payload.
**/
class TypedExactEnumConstructorSource {
	public static inline function marker():String
		return "$hxhx:exact-enum-constructor";

	public static function encode(owner:String, modulePath:String, declaration:String, constructor:String, callee:HxExpr, arguments:Array<HxExpr>):HxExpr {
		if (callee == null)
			throw "exact enum constructor marker requires its original call shape";
		return ECall(EUnsupported(marker()), [
			EString(owner == null ? "" : owner),
			EString(modulePath == null ? "" : modulePath),
			EString(declaration == null ? "" : declaration),
			EString(constructor == null ? "" : constructor),
			callee,
			EArrayDecl(arguments == null ? [] : arguments)
		]);
	}

	public static function decode(expression:HxExpr):Null<TypedExactEnumConstructorCall> {
		return switch (expression) {
			case ECall(EUnsupported(value), [
				EString(owner),
				EString(modulePath),
				EString(declaration),
				EString(constructor),
				callee,
				EArrayDecl(arguments)
			]) if (value == marker()):
				if (owner.length == 0 || modulePath.length == 0 || declaration.length == 0 || constructor.length == 0)
					throw "exact enum constructor marker has an incomplete typed identity";
				{
					owner: owner,
					modulePath: modulePath,
					declaration: declaration,
					constructor: constructor,
					callee: callee,
					arguments: arguments.copy()
				};
			case _:
				null;
		};
	}

	/** Recover the source spelling for targets that do not yet consume the exact owner. **/
	public static function ordinaryCall(exact:TypedExactEnumConstructorCall):HxExpr
		return ECall(exact.callee, exact.arguments.copy());
}
