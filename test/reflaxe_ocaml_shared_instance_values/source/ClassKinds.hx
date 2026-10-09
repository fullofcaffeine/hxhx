/** Declaration shapes whose construction and dispatch rules must remain distinct. */
interface Contract<T> {
	public function take(value:T):T;
}

interface ChildContract extends Contract<Int> {}

class Implementation implements Contract<Int> {
	public function new() {}

	public function take(value:Int):Int
		return value;
}

extern class External {
	public function new();
}

class ClassKinds {
	static function main():Void {}
}
