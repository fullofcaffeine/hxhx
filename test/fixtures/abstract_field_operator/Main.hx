/**
	A read of an unknown field on an abstract with an `@:op(a.b)` method calls that method with the
	field name, as in Haxe 4.3.7: `table.width` is `table.resolve("width")`. haxe.xml.Access reads
	`x.nodes.m` this way. The operations live in their own class, declared before `Main`, so that
	calls from `main` cannot supply the evidence.
**/
abstract Table(Map<String, Int>) {
	public inline function new()
		this = ["width" => 3, "height" => 4];

	@:op(a.b)
	public function resolve(name:String):Int
		return this.exists(name) ? this.get(name) : 0;
}

class Ops {
	/** `scale` is an Int only when `table.width` reads as the resolver's Int. **/
	public static function area(table:Table, scale)
		return table.width * table.height + scale;

	public static function missing(table:Table, fallback)
		return table.depth == 0 ? fallback : "deep";
}

class Main {
	static function main() {
		final table = new Table();
		Sys.println(Ops.area(table, 1));
		Sys.println(Ops.missing(table, "flat"));
	}
}
