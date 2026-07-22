/**
	Checked access to a variable declaration stored inside `HxExpr.EVars`.

	Why this helper exists:
	- a declaration contains an optional `HxExpr` initializer;
	- `HxExpr.EVars` contains declarations;
	- representing those two sides as separate generated OCaml types creates a
	  circular module dependency.

	The declaration therefore uses the recursive `HxExpr.EVariableDeclaration`
	constructor. These helpers keep callers readable and fail immediately if an
	invalid child is ever placed inside `EVars`.
**/
abstract HxExprVarDecl(HxExpr) {
	public static function make(name:String, typeHint:String, initializer:Null<HxExpr>, position:HxPos, isFinal:Bool = false, isStatic:Bool = false):HxExpr {
		return EVariableDeclaration(name == null ? "" : name, typeHint == null ? "" : typeHint, initializer, position == null ? HxPos.unknown() : position,
			isFinal, isStatic);
	}

	public static function getName(declaration:HxExpr):String
		return switch (declaration) {
			case EVariableDeclaration(name, _, _, _, _, _): name;
			case _: throw invalidMessage(declaration);
		};

	public static function getTypeHint(declaration:HxExpr):String
		return switch (declaration) {
			case EVariableDeclaration(_, typeHint, _, _, _, _): typeHint;
			case _: throw invalidMessage(declaration);
		};

	public static function getInitializer(declaration:HxExpr):Null<HxExpr>
		return switch (declaration) {
			case EVariableDeclaration(_, _, initializer, _, _, _): initializer;
			case _: throw invalidMessage(declaration);
		};

	public static function getPosition(declaration:HxExpr):HxPos
		return switch (declaration) {
			case EVariableDeclaration(_, _, _, position, _, _): position;
			case _: throw invalidMessage(declaration);
		};

	public static function getIsFinal(declaration:HxExpr):Bool
		return switch (declaration) {
			case EVariableDeclaration(_, _, _, _, isFinal, _): isFinal;
			case _: throw invalidMessage(declaration);
		};

	public static function getIsStatic(declaration:HxExpr):Bool
		return switch (declaration) {
			case EVariableDeclaration(_, _, _, _, _, isStatic): isStatic;
			case _: throw invalidMessage(declaration);
		};

	static function invalidMessage(declaration:HxExpr):String
		return "HxExpr.EVars contains a child that is not EVariableDeclaration: " + Std.string(declaration);
}
