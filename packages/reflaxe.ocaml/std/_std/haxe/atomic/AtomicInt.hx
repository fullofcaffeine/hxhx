package haxe.atomic;

/**
	Portable OCaml override for `haxe.atomic.AtomicInt`.

	This preserves the public API and single-thread behavior for stdlib parity,
	but it is not a hardware-atomic implementation yet.

	Contract note:
	- controlled by `-D ocaml_atomic_semantics=emulated` (default/only mode today).
	- this class must not be treated as a thread-level atomic primitive.
**/
class AtomicInt {
	var value:Int;

	public inline function new(value:Int):Void {
		this.value = value;
	}

	public inline function add(b:Int):Int {
		final original = value;
		value = original + b;
		return original;
	}

	public inline function sub(b:Int):Int {
		final original = value;
		value = original - b;
		return original;
	}

	public inline function and(b:Int):Int {
		final original = value;
		value = original & b;
		return original;
	}

	public inline function or(b:Int):Int {
		final original = value;
		value = original | b;
		return original;
	}

	public inline function xor(b:Int):Int {
		final original = value;
		value = original ^ b;
		return original;
	}

	public inline function compareExchange(expected:Int, replacement:Int):Int {
		final original = value;
		if (original == expected) {
			value = replacement;
		}
		return original;
	}

	public inline function exchange(value:Int):Int {
		final original = this.value;
		this.value = value;
		return original;
	}

	public inline function load():Int {
		return value;
	}

	public inline function store(value:Int):Int {
		this.value = value;
		return value;
	}
}
