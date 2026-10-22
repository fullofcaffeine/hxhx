/** Constructor annotations must not change the value initialized by an abstract body. */
class Main {
	static function main():Void {
		Sys.println(new OwnResult(7).read());
		Sys.println(new NoResult(11).read());
		Sys.println(new VoidResult(13).read());
		Sys.println(new IntResult(17).read());
		Sys.println(new StringResult(19).read());
		Sys.println(new GenericResult<String>("word").read());
	}
}

/** The written abstract result describes construction, not a value-returning body. */
abstract OwnResult(Int) {
	public function new(value:Int):OwnResult {
		this = value;
	}

	public function read():Int
		return this;
}

/** Omitted annotations still produce a body that completes without a returned value. */
abstract NoResult(Int) {
	public function new(value:Int) {
		this = value;
	}

	public function read():Int
		return this;
}

/** An explicit Void annotation preserves the same construction contract. */
abstract VoidResult(Int) {
	public function new(value:Int):Void {
		this = value;
	}

	public function read():Int
		return this;
}

/** Upstream accepts this annotation without changing the abstract's constructed type. */
abstract IntResult(Int) {
	public function new(value:Int):Int {
		this = value;
	}

	public function read():Int
		return this;
}

/** Even a different annotation must not replace either the constructed value or body completion. */
abstract StringResult(Int) {
	public function new(value:Int):String {
		this = value;
	}

	public function read():Int
		return this;
}

/** Generic construction retains its exact abstract parameter while initializing the backing array. */
abstract GenericResult<T>(Array<T>) {
	public function new(value:T):GenericResult<T> {
		this = [value];
	}

	public function read():T
		return this[0];
}
