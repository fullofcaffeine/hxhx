import Main;

class WrongArgument {
	@:generic static function get<Arg, Cls:haxe.Constraints.Constructible<Arg->Void>>(a:Arg, c:Class<Cls>):Cls
		return new Cls(a);

	static function main() {
		get(new Parent(), TakeChild);
	}
}
