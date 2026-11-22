using Lambda;

/**
	A structure's own method field wins over a static extension of the same name, as in Haxe 4.3.7:
	with `using Lambda;`, `access.has("x")` for `{function has(name:String):Bool;}` calls the
	structure's `has`, not `Lambda.has`. haxe.macro.TypeTools calls `cf.meta.has(":final")` this way.
	The operations live in their own class, declared before `Main`, so that calls from `main`
	cannot supply the evidence.
**/
typedef Access = {
	function has(name:String):Bool;
}

typedef Field = {
	var meta:Access;
}

class Holder {
	public final field:Field;

	public function new(field:Field)
		this.field = field;
}

class Ops {
	/** `flag` is a Bool only when `has` returns the structure's Bool. **/
	public static function marked(holder:Holder, flag)
		return holder.field.meta.has("final") == flag;

	/** `name` is a String only when the structure's `has(name:String)` is called. **/
	public static function named(holder:Holder, name)
		return holder.field.meta.has(name);
}

class Main {
	static function main() {
		final access:Access = {has: name -> name == "final"};
		final holder = new Holder({meta: access});
		Sys.println(Ops.marked(holder, true));
		Sys.println(Ops.named(holder, "other"));
	}
}
