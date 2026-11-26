class Box<T> {
	final value:T;

	public function new(value:T)
		this.value = value;

	public function wrap<S>(f:T->S):Box<S>
		return new Box(f(value));

	public function get():T
		return value;
}

class Main {
	static function main() {
		Sys.println(([1] : {function map<T>(s:Int->T):Array<T>;}).map(function(x) return x + 1)[0] == 2);
		Sys.println(([1] : {function map(s:Int->String):Array<String>;}).map(function(x) return "v" + x)[0]);
		final box:{function wrap<U>(f:Int->U):Box<U>;} = new Box(20);
		Sys.println(box.wrap(function(x) return x * 2).get());
	}
}
