/**
	A recursive typedef can reach a call expanded on one side and as its alias on the other.
	`joinAll(d.params, show)` passes `d.params` (an array of the alias `Decl`) and `show`, whose
	parameter is the expanded structure. Haxe 4.3.7 accepts both because they are the same type.
	`haxe.macro.Printer` does the same with `tpd.params.map(printTypeParamDecl)`; this fixture
	avoids `Array.map`, whose Stage3 lowering does not compile for this callback.
**/
typedef Decl = {
	var name:String;
	var ?params:Array<Decl>;
}

/** An enum payload of the recursive typedef; hxhx builds the payload as `[items]` (haxe.rtti.CType). **/
enum Tree {
	Group(items:Array<Decl>);
}

class Shapes {
	static function joinAll(items:Array<Decl>, render:Decl->String):String {
		var out = "";
		for (item in items)
			out += " " + render(item);
		return out;
	}

	public static function show(d:Decl):String
		return d.name + (d.params != null ? joinAll(d.params, show) : "");

	public static function children(d:Decl):Int
		return switch (d.params == null ? Group([]) : Group(d.params)) {
			case Group(items): items.length;
		};

	public static function nest(depth:Int):Decl
		return depth == 0 ? {name: "T"} : {name: "T" + depth, params: [nest(depth - 1), {name: "U"}]};
}

/** The observed operations take simple inputs; `Shapes` holds the recursive typedef. **/
class Ops {
	public static function describe(depth:Int)
		return Shapes.show(Shapes.nest(depth));

	public static function count(depth:Int)
		return Shapes.children(Shapes.nest(depth));
}

class Main {
	static function main() {
		Sys.println(Ops.describe(0));
		Sys.println(Ops.describe(2));
		Sys.println(Ops.count(0));
		Sys.println(Ops.count(2));
	}
}
