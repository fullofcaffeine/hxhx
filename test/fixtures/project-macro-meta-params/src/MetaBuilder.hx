#if macro
import haxe.macro.Context;
#end
import haxe.macro.Expr;

/**
	A project macro that defines modules whose fields carry metadata with parameters, in the shape
	of upstream `tests/unit` `UnitBuilder` (haxe_ocaml-xie5f): the field of a `*Utf8` spec gets
	`@:haxe.warning("-WDeprecated")`, and another field gets parameters of several kinds.
**/
class MetaBuilder {
	public static macro function generate(names:String):Expr {
		#if macro
		final created = [];
		final base:TypePath = {pack: [], name: "MetaBase"};
		function define(name:String) {
			final p = Context.currentPos();
			final utf8 = StringTools.endsWith(name, "Utf8");
			var func:Function = {
				args: [],
				ret: null,
				params: [],
				expr: utf8 ? macro Sys.println("spec " + $v{name} + " " + Old.value()) : macro Sys.println("spec " + $v{name})
			}
			var field = {
				name: "test",
				kind: FFun(func),
				pos: p,
				access: [APublic, AOverride],
				doc: null,
				meta: utf8 ? [{name: ":haxe.warning", params: [macro "-WDeprecated"], pos: p}] : [
					{name: ":probe", params: [macro 1, macro "two", macro [3, 4], macro {x: -5}, macro a.b.C], pos: p}
				]
			};
			var pack = ["spec"];
			var typeName = "Test" + name;
			Context.defineModule(pack.join(".") + "." + typeName, [
				{
					pack: pack,
					name: typeName,
					pos: p,
					kind: TDClass(base),
					fields: [field]
				}
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
}
