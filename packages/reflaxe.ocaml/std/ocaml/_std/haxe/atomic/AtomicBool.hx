package haxe.atomic;

/**
	Portable OCaml override for `haxe.atomic.AtomicBool`.

	This mirrors upstream bool/int conversion behavior on top of local `AtomicInt`.

	Contract note:
	- follows `AtomicInt` emulated semantics (`-D ocaml_atomic_semantics=emulated`).
	- preserves API behavior, not hardware/thread-level atomic guarantees.
**/
class AtomicBool {
	final inner:AtomicInt;

	public inline function new(value:Bool):Void {
		inner = new AtomicInt(toInt(value));
	}

	public inline function compareExchange(expected:Bool, replacement:Bool):Bool {
		return toBool(inner.compareExchange(toInt(expected), toInt(replacement)));
	}

	public inline function exchange(value:Bool):Bool {
		return toBool(inner.exchange(toInt(value)));
	}

	public inline function load():Bool {
		return toBool(inner.load());
	}

	public inline function store(value:Bool):Bool {
		return toBool(inner.store(toInt(value)));
	}

	inline function toInt(value:Bool):Int {
		return value ? 1 : 0;
	}

	inline function toBool(value:Int):Bool {
		return value == 1;
	}
}
