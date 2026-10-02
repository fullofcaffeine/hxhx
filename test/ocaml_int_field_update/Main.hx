/** Observes Int field mutations and the values returned by prefix and postfix updates. */
class Main {
	public var value:Int;
	public var calls:Int;

	public function new() {
		value = 10;
		calls = 0;
	}

	public function select():Main {
		calls = calls + 1;
		return this;
	}

	public function touch():Void {
		this.value++;
	}

	static function main():Void {
		final receiver = new Main();
		Sys.println(receiver.select().value++);
		Sys.println(receiver.value);
		Sys.println(++receiver.select().value);
		Sys.println(receiver.value);
		Sys.println(receiver.select().value--);
		Sys.println(--receiver.select().value);
		receiver.touch();
		Sys.println(receiver.value);
		Sys.println(receiver.calls);
		receiver.value = 2147483647;
		Sys.println(++receiver.value);
		Sys.println(receiver.value--);
		Sys.println(receiver.value);
	}
}
