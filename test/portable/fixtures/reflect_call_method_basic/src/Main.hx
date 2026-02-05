interface IFoo {
	public function mul(x:Int):Int;
}

class Impl implements IFoo {
	final k:Int;

	public function new(k:Int) {
		this.k = k;
	}

	public function mul(x:Int):Int {
		return k * x;
	}
}

class Main {
	static function add(x:Int, y:Int):Int {
		return x + y;
	}

	static function main() {
		final u = new Impl(3);
		final f:Dynamic = u.mul;
		final r1:Dynamic = Reflect.callMethod(u, f, [2]);

		final g:Dynamic = add;
		final r2:Dynamic = Reflect.callMethod(null, g, [1, 2]);

		Sys.println("r1=" + r1 + ",r2=" + r2);
	}
}

