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

	public function new(name:String, visibility:HxVisibility, isStatic:Bool, typeHint:String, init:Null<HxExpr>) {
		this.name = name;
		this.visibility = visibility;
		this.isStatic = isStatic;
		this.typeHint = typeHint == null ? "" : typeHint;
		this.init = init;
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
}
