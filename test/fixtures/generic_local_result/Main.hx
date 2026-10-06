/** An empty allocation needs later evidence for its element type. */
class Store<T> {
	var value:Null<T>;

	public function new() {
		value = null;
	}

	public function set(value:T):Void {
		this.value = value;
	}

	public function get():Null<T> {
		return value;
	}
}

/** Return contexts must reach the original allocation through aliases and branches. */
class Main {
	static function dynamicResult(value:Dynamic):Store<Dynamic> {
		var result = new Store();
		result.set(value);
		return result;
	}

	static function aliasResult():Store<String> {
		final result = new Store();
		final alias = result;
		return alias;
	}

	static function branchResult(first:Bool):Store<Int> {
		final left = new Store();
		final right = new Store();
		if (first)
			return left;
		return right;
	}

	static function localContext():String {
		final result = new Store();
		final typed:Store<String> = result;
		typed.set("typed");
		return typed.get();
	}

	static function main():Void {
		Sys.println(dynamicResult("ok").get());
		Sys.println(aliasResult().get() == null);
		Sys.println(branchResult(true).get() == null);
		Sys.println(branchResult(false).get() == null);
		Sys.println(localContext());
	}
}
