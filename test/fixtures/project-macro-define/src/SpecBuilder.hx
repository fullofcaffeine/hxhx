#if macro
import haxe.macro.Context;
#end
import haxe.macro.Expr;

/**
	Project macros that define new modules, in the shape of upstream `tests/unit` `UnitBuilder`:
	untyped records built in a local function, `FFun`, `TDClass` with a superclass, `INormal` and
	`IAll` imports, and `new $tp()` for each defined class. `registry` defines a type with
	`defineType`. The `Context` import and the macro bodies are inside `#if macro`
	(see `test/fixtures/project-macro-context`).
**/
class SpecBuilder {
	public static macro function generate(names:String):Expr {
		#if macro
		final created = [];
		final base:TypePath = {pack: [], name: "SpecBase"};
		function define(name:String) {
			final p = Context.currentPos();
			var func:Function = {
				args: [],
				ret: null,
				params: [],
				expr: macro Sys.println("spec " + $v{name} + " " + SpecTools.describe() + " " + label())
			}
			var field = {
				name: "test",
				kind: FFun(func),
				pos: p,
				access: [APublic, AOverride],
				doc: null,
				meta: []
			};
			var pack = ["spec"];
			var typeName = "Test" + name.charAt(0).toUpperCase() + name.substr(1);
			Context.defineModule(pack.join(".") + "." + typeName, [
				{
					pack: pack,
					name: typeName,
					pos: p,
					kind: TDClass(base),
					fields: [field]
				}
			], [
				{path: [{pos: p, name: "tools"}, {pos: p, name: "SpecTools"}], mode: INormal},
				{path: [{pos: p, name: "tools"}, {pos: p, name: "SpecTools"}], mode: IAll}
			]);
			var tp:TypePath = {pack: pack, name: typeName};
			created.push(macro new $tp());
		}
		for (name in names.split(","))
			define(name);
		return macro $a{created};
		#else
		return null;
		#end
	}

	public static macro function registry(count:Int):Expr {
		#if macro
		final p = Context.currentPos();
		final intType:TypePath = {pack: [], name: "Int"};
		Context.defineType({
			pack: ["spec"],
			name: "Registry",
			pos: p,
			kind: TDClass(),
			fields: [
				{
					name: "count",
					kind: FVar(TPath(intType), macro $v{count}),
					pos: p,
					access: [APublic, AStatic]
				}
			]
		});
		return macro spec.Registry.count;
		#else
		return null;
		#end
	}
}
