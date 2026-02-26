package haxe.atomic;

/**
	Portable OCaml override for `haxe.atomic.AtomicObject`.

	This preserves load/store/exchange/compareExchange API behavior for object
	values in portable lanes.
**/
class AtomicObject<T:{}> {
	var value:T;

	public function new(value:T):Void {
		this.value = value;
	}

	public function compareExchange(expected:T, replacement:T):T {
		final original = value;
		if (original == expected) {
			value = replacement;
		}
		return original;
	}

	public function exchange(nextValue:T):T {
		final original = this.value;
		this.value = nextValue;
		return original;
	}

	public function load():T {
		return value;
	}

	public function store(nextValue:T):T {
		this.value = nextValue;
		return nextValue;
	}
}
