/** Keep results separate from caller storage and count every effectful receiver. */
class Main {
	public static var arrayCalls:Int = 0;
	public static var arrayPostfix:Int = 0;
	public static var arrayPrefix:Int = 0;
	public static var arrayStored:Int = 0;
	public static var assignedPostfix:Int = 0;
	public static var assignedResult:Int = 0;
	public static var assignedStored:Int = 0;
	public static var fieldCalls:Int = 0;
	public static var fieldPostfix:Int = 0;
	public static var fieldPrefix:Int = 0;
	public static var fieldStored:Int = 0;
	public static var indexCalls:Int = 0;
	public static var localPostfix:Int = 0;
	public static var localPrefix:Int = 0;
	public static var localStored:Int = 0;
	public static var rhsCalls:Int = 0;
	public static var rhsResult:Int = 0;
	public static var rhsStored:Int = 0;
	public static var shared:Changing = new Changing(5);

	public static function mutateOther():Int {
		rhsCalls++;
		shared = new Changing(100);
		return 2;
	}

	public static function main():Void {
		var local:Step = new Step(12);
		final before = ++local;
		localPrefix = before.get();
		final after = local++;
		localPostfix = after.get();
		localStored = local.get();
		var assigned = new Assigned(8);
		final changed = ++assigned;
		assignedResult = changed.get();
		final assignedOld = assigned++;
		assignedPostfix = assignedOld.get();
		assignedStored = assigned.get();
		final counter = new Counter();
		final fieldBefore = ++counter.chooseHolder().step;
		final fieldAfter = counter.chooseHolder().step++;
		fieldPrefix = fieldBefore.get();
		fieldPostfix = fieldAfter.get();
		fieldStored = counter.holder.step.get();
		fieldCalls = counter.fieldCalls;
		final arrayBefore = ++counter.chooseArray()[counter.chooseIndex()];
		final arrayAfter = counter.chooseArray()[counter.chooseIndex()]++;
		arrayPrefix = arrayBefore.get();
		arrayPostfix = arrayAfter.get();
		arrayStored = counter.values[0].get();
		arrayCalls = counter.arrayCalls;
		indexCalls = counter.indexCalls;
		final saved = ++shared;
		rhsResult = saved.get();
		rhsStored = shared.get();
	}
}

/** These helpers have no implicit conversion headers that could authorize a public cast. */
abstract Step(Int) {
	public inline function new(value:Int)
		this = value;

	@:op(++A) public inline function advanceBefore():Step {
		this += 10;
		return cast this;
	}

	@:op(A++) public inline function advanceAfter():Step {
		var old = this;
		this += 100;
		return cast old;
	}

	public function get():Int
		return this;
}

/** A simple assignment must also write the abstract's original caller storage. */
abstract Assigned(Int) {
	public inline function new(value:Int)
		this = value;

	@:op(++A) public inline function advance():Assigned {
		this = this + 3;
		return cast this;
	}

	@:op(A++) public inline function previous():Assigned {
		return cast this
		++;
	}

	public function get():Int
		return this;
}

/** The old value is read before the RHS overwrites the same source field. */
abstract Changing(Int) {
	public inline function new(value:Int)
		this = value;

	@:op(++A) public inline function advance():Changing {
		this += Main.mutateOther();
		return cast this;
	}

	public function get():Int
		return this;
}

/** One ordinary field destination shared by prefix and postfix updates. */
class Holder {
	public var step:Step = new Step(5);

	public function new() {}
}

/** Unary field and indexed places have distinct upstream evaluation counts. */
class Counter {
	public var arrayCalls:Int = 0;
	public var fieldCalls:Int = 0;
	public var indexCalls:Int = 0;
	public var holder:Holder = new Holder();
	public var values:Array<Step> = [new Step(4)];

	public function new() {}

	public function chooseHolder():Holder {
		fieldCalls++;
		return holder;
	}

	public function chooseArray():Array<Step> {
		arrayCalls++;
		return values;
	}

	public function chooseIndex():Int {
		indexCalls++;
		return 0;
	}
}
