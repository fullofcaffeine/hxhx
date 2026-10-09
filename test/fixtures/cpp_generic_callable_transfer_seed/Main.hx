/** Preserve callback identity and generic null until a concrete scalar storage boundary. */
class Main {
	static function main():Void {
		var calls = 0;
		final original = function():Int {
			calls++;
			return 7;
		};
		final ints = new Slot<Int>();
		ints.produce = original;
		final roundTrip:() -> Int = ints.produce;
		if (original != roundTrip || roundTrip() != 7 || calls != 1)
			throw "generic callback changed identity, result, or invocation count";
		final genericInt = ints.empty();
		final typedInt:() -> Int = genericInt;
		final nullableInt:() -> Null<Int> = typedInt;
		final preservedInt:Null<Int> = nullableInt();
		final assignedInt:Int = typedInt();
		if (preservedInt != null || assignedInt != 0 || genericInt != typedInt || typedInt != nullableInt)
			throw "Int callback alias lost generic null or identity";
		final bools = new Slot<Bool>();
		final genericBool = bools.empty();
		final typedBool:() -> Bool = genericBool;
		final nullableBool:() -> Null<Bool> = typedBool;
		final preservedBool:Null<Bool> = nullableBool();
		final assignedBool:Bool = typedBool();
		if (preservedBool != null || assignedBool != false || genericBool != typedBool)
			throw "Bool callback alias lost generic null or identity";
		verifyConditional(false, typedInt, typedBool);
		verifyConditional(true, typedInt, typedBool);
		verifySwitch(typedInt, typedBool);
		var choose = false;
		final skipped:Int = choose ? original() : 11;
		if (skipped != 11 || calls != 1)
			throw "conditional invoked the unselected callback";
		choose = true;
		final selected:Int = choose ? original() : 11;
		if (selected != 7 || calls != 2)
			throw "conditional changed callback invocation count";
		ints.transform = function(value:Int):Int return value;
		if (ints.applyNull() != 0)
			throw "concrete callback did not default its Int parameter";
		bools.transform = function(value:Bool):Bool return value;
		if (bools.applyNull() != false)
			throw "concrete callback did not default its Bool parameter";
		final absent:() -> Int = null;
		ints.produce = absent;
		if (ints.produce != null)
			throw "null callback acquired an adapter allocation";
		verifyReassignment();
		verifyReferences();
	}

	/** Replacing a generic field must not retarget a previously stored scalar callback alias. */
	static function verifyReassignment():Void {
		var calls = 0;
		final first = function():Int {
			calls++;
			return 11;
		};
		final second = function():Int {
			calls++;
			return 23;
		};
		final ints = new Slot<Int>();
		ints.produce = first;
		final alias = ints.keep(ints.produce);
		ints.produce = second;
		if (alias != first || ints.produce != second || alias == ints.produce)
			throw "integer reassignment changed callback identity";
		if (ints.invoke(alias) != 11 || ints.invoke(ints.produce) != 23 || calls != 2)
			throw "integer reassignment changed invocation or result";
		final bools = new Slot<Bool>();
		final yes = function():Bool return true;
		final no = function():Bool return false;
		bools.produce = yes;
		final previous = bools.keep(bools.produce);
		bools.produce = no;
		if (previous != yes || bools.produce != no || !bools.invoke(previous) || bools.invoke(bools.produce))
			throw "Boolean reassignment changed callback identity or result";
	}

	/** Generic callback fields and parameters retain reference identity, captured state, and null. */
	static function verifyReferences():Void {
		var calls = 0;
		var selected = new Token(7);
		final initial = selected;
		final reader = function():Token {
			calls++;
			return selected;
		};
		final references = new Slot<Token>();
		references.produce = reader;
		final alias = references.keep(references.produce);
		if (alias != reader || references.invoke(alias) != initial || calls != 1)
			throw "reference callback lost identity or invocation count";
		selected = new Token(9);
		if (alias() != selected || alias().value != 9 || calls != 3)
			throw "reference callback lost its mutable capture";
		final replacement = function():Token return initial;
		references.produce = replacement;
		if (references.produce != replacement
			|| alias == references.produce
			|| references.invoke(alias) != selected
			|| references.invoke(references.produce) != initial
			|| calls != 4)
			throw "reference reassignment changed an existing alias";
		references.transform = function(value:Token):Token return value;
		if (references.applyNull() != null || references.empty()() != null)
			throw "reference callback converted generic null";
		final absent:() -> Token = null;
		references.produce = absent;
		if (references.produce != null || alias() != selected || calls != 5)
			throw "clearing a reference callback invalidated its alias";
	}

	/** A conditional preserves its selected callback value until the destination chooses scalar coercion. */
	static function verifyConditional(choose:Bool, read:() -> Int, readBool:() -> Bool):Void {
		final first:Null<Int> = choose ? 7 : read();
		final second:Null<Int> = choose ? read() : 7;
		final concrete:Int = choose ? 7 : read();
		if (choose) {
			if (first != 7 || second != null || concrete != 7)
				throw "true conditional changed integer null transport";
		} else if (first != null || second != 7 || concrete != 0)
			throw "false conditional changed integer null transport";
		final firstBool:Null<Bool> = choose ? true : readBool();
		final secondBool:Null<Bool> = choose ? readBool() : true;
		final concreteBool:Bool = choose ? true : readBool();
		if (choose) {
			if (firstBool != true || secondBool != null || concreteBool != true)
				throw "true conditional changed Boolean null transport";
		} else if (firstBool != null || secondBool != true || concreteBool != false)
			throw "false conditional changed Boolean null transport";
	}

	/** Switching on a generic null callback result must not select zero or false. */
	static function verifySwitch(read:() -> Int, readBool:() -> Bool):Void {
		final direct = switch (read()) {
			case 0: 1;
			default: 2;
		};
		final nullable:() -> Null<Int> = read;
		final missing = switch (nullable()) {
			case null: 3;
			case 0: 4;
			default: 5;
		};
		final boolean = switch (readBool()) {
			case false: 6;
			default: 7;
		};
		if (direct != 2 || missing != 3 || boolean != 7)
			throw "switch coerced generic null before selecting its arm";
	}
}

/** Generic fields and methods use the same callable allocation through all storage views. */
class Slot<T> {
	public var produce:() -> T;
	public var transform:T->T;

	public function new() {}

	public function empty():() -> T
		return function():T return null;

	public function applyNull():T
		return transform(null);

	public function keep(callback:() -> T):() -> T
		return callback;

	public function invoke(callback:() -> T):T
		return callback();
}

/** Distinct mutable objects make reference identity observable without target-specific inspection. */
class Token {
	public var value:Int;

	public function new(value:Int)
		this.value = value;
}
