/** Value used to exercise `Constructible<String -> Void>` generic constraints. **/
class GenericToken {
	public final value:String;

	public function new(value:String) {
		this.value = value;
	}
}

/** Zero-argument constructor control for module-local same-name ownership. **/
class ZeroCtorSibling {
	public final value:Int;

	public function new() {
		value = 7;
	}
}

/** Parameterized constructor control sharing the method name `new`. **/
class ArgCtorSibling {
	public final value:String;

	public function new(value:String) {
		this.value = value;
	}
}

/** Constrained generic helper whose declaration, body, and calls must keep two arguments. **/
class GenericArityOwner {
	@:generic public static function appendClone<A:haxe.Constraints.Constructible<String->Void>, B:Array<A>>(seed:A, values:B):B {
		final clone = new A("copy");
		values.push(clone);
		return values;
	}

	public static function zero():Int {
		return 0;
	}
}

/** Upstream Haxe 4.3.7 behavior oracle for constrained generic arity. **/
class Main {
	static function emit(id:String, value:Dynamic):Void {
		Sys.println(id + "|value|" + Std.string(value));
	}

	static function main():Void {
		final values = GenericArityOwner.appendClone(new GenericToken("seed"), [new GenericToken("first")]);
		emit("constrained-generic-arity-01:length", values.length);
		emit("constrained-generic-arity-01:clone", values[1].value);
		emit("constrained-generic-arity-01:zero", GenericArityOwner.zero());
		emit("constrained-generic-arity-01:zero-ctor", new ZeroCtorSibling().value);
		emit("constrained-generic-arity-01:arg-ctor", new ArgCtorSibling("arg").value);
	}
}
