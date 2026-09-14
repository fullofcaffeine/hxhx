/** Supplies effectful nullable Boolean values for string-conversion checks. */
class Probe {
	public var calls:Int;

	public function new()
		calls = 0;

	public function next():Null<Bool> {
		this.calls = this.calls + 1;
		return this.calls == 1 ? true : this.calls == 2 ? false : null;
	}
}

/** Checks Boolean spelling without confusing Python Booleans with integer values. */
class Main {
	static function main():Void {
		final probe = new Probe();
		Sys.println(Std.string(true));
		Sys.println(Std.string(false));
		var value:Null<Bool> = true;
		Sys.println(Std.string(value));
		value = false;
		Sys.println(Std.string(value));
		value = null;
		Sys.println(Std.string(value));
		Sys.println(Std.string(probe.next()));
		Sys.println(Std.string(probe.next()));
		Sys.println(Std.string(probe.next()));
		Sys.println(probe.calls);
		Sys.println(Std.string(1));
		Sys.println(Std.string(0));
		Sys.println(Std.string("True"));
	}
}
