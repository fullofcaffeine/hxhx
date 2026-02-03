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
	static function main() {
		// User-class method as value.
		final u = new Impl(3);
		final f = u.mul;
		final uResult = f(1);

		// Interface/dispatch receiver method as value.
		final i:IFoo = new Impl(10);
		final g = i.mul;
		final iResult = g(3);

		Sys.println("u=" + uResult + ",i=" + iResult);
	}
}

