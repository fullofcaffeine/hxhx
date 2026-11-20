/**
	A callback argument keeps its expected type when a later optional argument is left out,
	as in Haxe 4.3.7: `timer.start(() -> Counter.add(2), ms)` for
	`start(callback:() -> Void, ms:Int, ?repeat:Int)`. eval's `sys.thread.EventLoop` calls
	`timer.start(() -> {...}, Std.int(timeout * 1000))` this way. The operations live in
	their own class, declared before `Main`, so that calls from `main` cannot supply the evidence.
**/
class Timer {
	public function new() {}

	public function start(callback:() -> Void, ms:Int, ?repeat:Int):Int {
		callback();
		return repeat == null ? ms : ms + repeat;
	}
}

class Counter {
	public static var total = 0;

	public static function add(amount:Int):Int {
		total += amount;
		return total;
	}
}

class Ops {
	/** The callback body is a value of type Int, where the parameter returns Void. **/
	public static function counted(timer:Timer, ms)
		return timer.start(() -> Counter.add(2), ms);

	/** The callback body is a Void call. **/
	public static function printed(timer:Timer, ms)
		return timer.start(() -> Sys.println("tick"), ms);

	public static function repeated(timer:Timer, ms, repeat)
		return timer.start(() -> Counter.add(1), ms, repeat);
}

class Main {
	static function main() {
		final timer = new Timer();
		Sys.println(Ops.counted(timer, 10));
		Sys.println(Ops.printed(timer, 20));
		Sys.println(Ops.repeated(timer, 30, 5));
		Sys.println(Counter.total);
	}
}
