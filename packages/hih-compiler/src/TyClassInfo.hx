/**
	Class/type metadata used by the Stage 3 bootstrap typer.

	Why
	- Stage 3.2 (typer core) can type locals and primitive operators, but it
	  treats fields/calls as `Unknown`.
	- Stage 3.3 (this bead) introduces “module surface indexing” so we can type:
	  - static calls through imports (`Util.ping()`)
	  - instance field access (`this.x`)
	  - basic construction (`new Point(...)`)

	What
	- A nominal type identity (`fullName`), plus:
	  - declared fields (`name -> TyType`)
	  - declared static methods (`name -> TyFunSig`)
	  - declared instance methods (`name -> TyFunSig`)

	How
	- This is intentionally *not* upstream Haxe typing. It is a bootstrap index
	  built from parsed declarations so we can get deterministic types early.
**/
class TyClassInfo {
	final fullName:String;
	final shortName:String;
	final modulePath:String;
	final fields:haxe.ds.StringMap<TyType>;
	final staticMethods:haxe.ds.StringMap<TyFunSig>;
	final instanceMethods:haxe.ds.StringMap<TyFunSig>;

	public function new(
		fullName:String,
		shortName:String,
		modulePath:String,
		fields:haxe.ds.StringMap<TyType>,
		staticMethods:haxe.ds.StringMap<TyFunSig>,
		instanceMethods:haxe.ds.StringMap<TyFunSig>
	) {
		this.fullName = fullName;
		this.shortName = shortName;
		this.modulePath = modulePath;
		// Bootstrap note (OCaml target):
		// Avoid null-coalescing/conditional initialization here. Some bring-up
		// compiler modes erase generic types to `Obj.t`, and conditionals can
		// force OCaml to infer a concrete `Hashtbl.t` that then fails to unify
		// with the erased field type.
		//
		// Callers are expected to pass empty maps instead of `null`.
		this.fields = fields;
		this.staticMethods = staticMethods;
		this.instanceMethods = instanceMethods;
	}

	public function getFullName():String return fullName;
	public function getShortName():String return shortName;
	public function getModulePath():String return modulePath;

	public function hasField(name:String):Bool return fields.exists(name);
	public function fieldType(name:String):Null<TyType> return fields.exists(name) ? fields.get(name) : null;

	public function staticMethod(name:String):Null<TyFunSig> return staticMethods.exists(name) ? staticMethods.get(name) : null;
	public function instanceMethod(name:String):Null<TyFunSig> return instanceMethods.exists(name) ? instanceMethods.get(name) : null;
}
