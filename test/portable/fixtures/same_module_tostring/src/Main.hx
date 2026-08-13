class Main {
	static function main():Void {
		Sys.println("same=" + Std.string(new NamedValue(2)));
		Sys.println("separate=" + Std.string(new SeparateValue(3)));
	}
}

class NamedValue {
	final value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function toString():String {
		return 'named:$value';
	}
}
