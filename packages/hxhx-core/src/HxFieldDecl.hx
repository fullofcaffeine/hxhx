/**
	Class field declaration for the Stage 3/4 bootstrap AST.

	Why
	- Stage 3 typing needs to represent instance/static fields so we can type:
	  - `this.x`
	  - `obj.x`
	  - basic constructor initialization patterns (`this.x = arg`)
	- Upstream Haxe unit code (and real projects) use fields heavily; treating
	  them as “unknown” prevents meaningful typing beyond trivial functions.

	What
	- A minimal subset:
	  - name
	  - visibility (`public`/`private`)
	  - `static` flag
	  - optional raw type hint text (kept as-is until we parse full type grammar)

	How
	- Initial bootstrapping treats fields as “declared slots” (no property
	  getters/setters, no complex metadata semantics).
**/
class HxFieldDecl {
	public final name:String;
	public final visibility:HxVisibility;
	public final isStatic:Bool;
	public final typeHint:String;
	public final init:Null<HxExpr>;
	public final metadata:Array<String>;
	public final pos:HxPos;
	public final endPos:HxPos;
	public final isFinal:Bool;
	public final propertyGet:String;
	public final propertySet:String;
	public final initText:String;

	public function new(name:String, visibility:HxVisibility, isStatic:Bool, typeHint:String, init:Null<HxExpr>, ?metadata:Array<String>, ?pos:HxPos,
			?endPos:HxPos, ?isFinal:Bool, ?propertyGet:String, ?propertySet:String, ?initText:String) {
		this.name = name;
		this.visibility = visibility;
		this.isStatic = isStatic;
		this.typeHint = typeHint == null ? "" : typeHint;
		this.init = init;
		this.metadata = metadata == null ? [] : metadata;
		this.pos = pos == null ? HxPos.unknown() : pos;
		this.endPos = endPos == null ? this.pos : endPos;
		this.isFinal = isFinal == null ? false : isFinal;
		this.propertyGet = propertyGet == null ? "" : propertyGet;
		this.propertySet = propertySet == null ? "" : propertySet;
		this.initText = initText == null ? "" : initText;
	}

	public static function getName(f:HxFieldDecl):String
		return f.name;

	public static function getVisibility(f:HxFieldDecl):HxVisibility
		return f.visibility;

	public static function getIsStatic(f:HxFieldDecl):Bool
		return f.isStatic;

	public static function getTypeHint(f:HxFieldDecl):String
		return f.typeHint;

	public static function getInit(f:HxFieldDecl):Null<HxExpr>
		return f.init;

	public static function getMetadata(f:HxFieldDecl):Array<String>
		return f.metadata;

	public static function getPos(f:HxFieldDecl):HxPos
		return f.pos;

	public static function getEndPos(f:HxFieldDecl):HxPos
		return f.endPos;

	public static function getIsFinal(f:HxFieldDecl):Bool
		return f.isFinal;

	public static function getPropertyGet(f:HxFieldDecl):String
		return f.propertyGet;

	public static function getPropertySet(f:HxFieldDecl):String
		return f.propertySet;

	public static function getInitText(f:HxFieldDecl):String
		return f.initText;
}
