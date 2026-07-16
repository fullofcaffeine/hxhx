/**
	Original upstream-oracle fixture for binary abstract-operator semantics.

	The arbitrary helper names make selection by method spelling impossible. The
	event log also exposes source evaluation order separately from helper argument
	order, including the commutative and compound-assignment cases.
**/
class EventLog {
	public static var value:String = "";

	public static function reset():Void {
		value = "";
	}

	public static function note(label:String):Void {
		value += label;
	}

	public static function number(label:String, value:Int):Int {
		note(label);
		return value;
	}

	public static function text(label:String, value:String):String {
		note(label);
		return value;
	}
}

abstract Ticket(Int) from Int to Int {
	public inline function new(value:Int) {
		this = value;
	}

	public function get():Int {
		return this;
	}

	@:op(A + B)
	public static function mergeArbitrarily(left:Ticket, right:Ticket):Ticket {
		EventLog.note("M");
		return new Ticket(left.get() + right.get() + 10);
	}

	@:commutative
	@:op(A * B)
	public static function decorateArbitrarily(ticket:Ticket, text:String):String {
		EventLog.note("H");
		var result = "";
		for (_ in 0...ticket.get())
			result += text;
		return result;
	}

	@:op(A / B)
	public static function trimArbitrarily(text:String, ticket:Ticket):String {
		EventLog.note("T");
		return text.substr(0, ticket.get());
	}

	@:op(A += B)
	public static function advanceArbitrarily(ticket:Ticket, amount:Int):Ticket {
		EventLog.note("A");
		return new Ticket(ticket.get() + amount + 100);
	}
}

class ParcelPayload {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

abstract Parcel(ParcelPayload) from ParcelPayload to ParcelPayload {
	public inline function new(value:ParcelPayload) {
		this = value;
	}

	public function get():ParcelPayload {
		return this;
	}

	@:op(A + B)
	public static function uniteArbitrarily(left:Parcel, right:Parcel):Parcel {
		EventLog.note("U");
		return new ParcelPayload(left.get().value + right.get().value);
	}

	@:op(A * B)
	public static function enlargeArbitrarily(parcel:Parcel, factor:Int):Parcel {
		EventLog.note("E");
		return new ParcelPayload(parcel.get().value * factor);
	}

	@:op(A *= B)
	public static function enlargeInPlaceArbitrarily(parcel:Parcel, factor:Int):Parcel {
		EventLog.note("Q");
		parcel.get().value *= factor;
		return parcel;
	}
}

abstract Distance(Int) from Int to Int {
	public inline function new(value:Int) {
		this = value;
	}

	public function get():Int {
		return this;
	}

	@:op(A - B)
	public function reduceArbitrarily(amount:Int):Distance {
		EventLog.note("D");
		return new Distance(this - amount);
	}

	@:op(A += B)
	public inline function mutateArbitrarily(amount:Int):Void {
		EventLog.note("V");
		this += amount;
	}
}

class Main {
	static var indexCalls:Int = 0;

	static function ticket(label:String, value:Int):Ticket {
		EventLog.note(label);
		return new Ticket(value);
	}

	static function parcel(label:String, value:Int):Parcel {
		EventLog.note(label);
		return new Parcel(new ParcelPayload(value));
	}

	static function chooseIndex():Int {
		EventLog.note("I");
		indexCalls++;
		return 0;
	}

	static function printResult(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value + "|" + EventLog.value);
		#else
		Sys.println(value + "|" + EventLog.value);
		#end
	}

	static function main():Void {
		EventLog.reset();
		var merged = ticket("L", 2) + ticket("R", 3);
		printResult(Std.string(merged.get()));

		EventLog.reset();
		var direct = ticket("L", 3) * EventLog.text("R", "x");
		printResult(direct);

		EventLog.reset();
		var reversed = EventLog.text("L", "y") * ticket("R", 2);
		printResult(reversed);

		EventLog.reset();
		var trimmed = EventLog.text("L", "abcdef") / ticket("R", 3);
		printResult(trimmed);

		EventLog.reset();
		var local = new Ticket(1);
		var localResult:Ticket = (local += EventLog.number("R", 2));
		printResult(localResult.get() + ":" + local.get());

		EventLog.reset();
		indexCalls = 0;
		var values = [new Ticket(4)];
		var indexedResult:Ticket = (values[chooseIndex()] += EventLog.number("R", 3));
		printResult(indexedResult.get() + ":" + values[0].get() + ":" + indexCalls);

		EventLog.reset();
		var united = parcel("L", 4) + parcel("R", 5);
		printResult(Std.string(united.get().value));

		EventLog.reset();
		var enlarged = parcel("L", 6) * EventLog.number("R", 3);
		printResult(Std.string(enlarged.get().value));

		EventLog.reset();
		var mutableParcel = parcel("L", 7);
		var parcelResult:Parcel = (mutableParcel *= EventLog.number("R", 4));
		printResult(parcelResult.get().value + ":" + mutableParcel.get().value);

		EventLog.reset();
		var distance = new Distance(20);
		var reduced = distance - EventLog.number("R", 3);
		printResult(reduced.get() + ":" + distance.get());

		EventLog.reset();
		var mutableDistance = new Distance(8);
		mutableDistance += EventLog.number("R", 5);
		printResult(Std.string(mutableDistance.get()));
	}
}
