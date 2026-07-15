/** Value whose String constructor proves `Constructible<String -> Void>`. **/
class RelationToken {
	public final value:String;

	public function new(value:String) {
		this.value = value;
	}
}

/** Upstream Haxe 4.3.7 oracle for a generic constraint relating `B` to `Array<A>`. **/
class Main {
	@:generic static function appendClone<A:haxe.Constraints.Constructible<String->Void>, B:Array<A>>(seed:A, values:B):B {
		final clone = new A("copy");
		values.push(clone);
		return values;
	}

	static function main():Void {
		final populated = appendClone(new RelationToken("seed"), [new RelationToken("first")]);
		Sys.println(populated[0].value + "|" + populated[1].value);

		final empty = appendClone(new RelationToken("seed"), []);
		Sys.println(empty[0].value);
	}
}
