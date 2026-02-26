import haxe.atomic.AtomicBool;
import haxe.atomic.AtomicInt;
import haxe.atomic.AtomicObject;

private class Box {
	public var label:String;

	public function new(label:String) {
		this.label = label;
	}
}

class Main {
	static function main() {
		final atomicInt = new AtomicInt(3);
		Sys.println("int.add.old=" + atomicInt.add(2));
		Sys.println("int.load=" + atomicInt.load());
		Sys.println("int.compare.old=" + atomicInt.compareExchange(5, 9));
		Sys.println("int.load2=" + atomicInt.load());
		Sys.println("int.store=" + atomicInt.store(4));
		Sys.println("int.exchange.old=" + atomicInt.exchange(6));
		Sys.println("int.final=" + atomicInt.load());

		final atomicBool = new AtomicBool(false);
		Sys.println("bool.load=" + atomicBool.load());
		Sys.println("bool.store=" + atomicBool.store(true));
		Sys.println("bool.exchange.old=" + atomicBool.exchange(false));
		Sys.println("bool.final=" + atomicBool.load());

		final first = new Box("first");
		final second = new Box("second");
		final atomicObject = new AtomicObject<Box>(first);
		Sys.println("obj.load.isFirst=" + (atomicObject.load() == first));
		Sys.println("obj.compare.old.isFirst=" + (atomicObject.compareExchange(second, first) == first));
		Sys.println("obj.after.compare.isFirst=" + (atomicObject.load() == first));
		Sys.println("obj.exchange.old.isFirst=" + (atomicObject.exchange(second) == first));
		Sys.println("obj.final.isSecond=" + (atomicObject.load() == second));
	}
}
