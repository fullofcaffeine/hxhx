/** Generic runtime tests distinguish the concrete operand without changing runtime target identity. */
class Main {
	public static var evaluations:Int = 0;

	static function main():Void {
		final ints = new Inspector<Int>();
		final bools = new Inspector<Bool>();
		final strings = new Inspector<String>();
		final maps = new Inspector<Map<Int, String>>();
		final otherMaps = new Inspector<Map<String, Int>>();
		if (ints.check(7) || bools.check(false) || strings.check("text"))
			throw "primitive claimed Map identity";
		final value = [1 => "one"];
		if (!maps.check(value) || !maps.test(value) || !maps.viaClosure(value))
			throw "generic Map lost its runtime family";
		if (otherMaps.check(["one" => 1]))
			throw "Map families were conflated";
		final missing:Map<Int, String> = null;
		if (maps.check(missing) || maps.test(missing))
			throw "null claimed Map identity";
		if (!maps.withEffect(function():Map<Int, String> {
			evaluations = evaluations + 1;
			return [2 => "two"];
		}))
			throw "effectful Map operand lost its family";
		if (ints.withEffect(function():Int {
			evaluations = evaluations + 1;
			return 9;
		}))
			throw "mismatched operand claimed Map identity";
		if (evaluations != 2)
			throw "runtime test skipped or repeated operand effects";
		final inherited = new MapInspector();
		if (!inherited.check(value))
			throw "inherited field lost its applied operand type";
		final objects = new Inspector<Payload>();
		if (objects.check(new Payload()))
			throw "ordinary object claimed Map identity";
	}
}

/** Similar source operations have distinct function and field owners. */
class Inspector<T> {
	public var check:T->Bool = function(value:T):Bool return value is haxe.ds.IntMap;
	public var alsoCheck:T->Bool = function(value:T):Bool return value is haxe.ds.IntMap;
	public var withEffect:(() -> T) -> Bool = function(read:() -> T):Bool return read() is haxe.ds.IntMap;

	public function new() {}

	public function test(value:T):Bool
		return value is haxe.ds.IntMap;

	public function viaClosure(value:T):Bool {
		final run = function(item:T):Bool return item is haxe.ds.IntMap;
		return run(value);
	}
}

/** An inherited initializer still uses its generic declaring class's arguments. */
class MapInspector extends Inspector<Map<Int, String>> {}

/** Its ordinary instance representation cannot select a standard Map family. */
class Payload {
	public function new() {}
}
