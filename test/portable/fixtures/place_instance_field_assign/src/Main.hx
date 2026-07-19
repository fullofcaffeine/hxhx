/** Focused executable proof for value-producing instance-field assignment. */
class Main {
	static final holder = new Holder();
	static final events:Array<String> = [];

	static function receiver():Holder {
		events.push("receiver");
		return holder;
	}

	static function rhs():Int {
		events.push("rhs");
		return 7;
	}

	static function main():Void {
		final result = receiver().value = rhs();
		Sys.println("result=" + result + " final=" + holder.value + " events=" + events.join(",") + " abstract=" + abstractControl());

		events.resize(0);
		final compoundResult = receiver().value += rhsMutating();
		Sys.println("compound=" + compoundResult + " final=" + holder.value + " events=" + events.join(","));
	}

	static function abstractControl():String {
		final abstractHolder = new AbstractHolder();
		final result = abstractHolder.value = 9;
		return (result : Int) + "/" + (abstractHolder.value : Int);
	}

	static function rhsMutating():Int {
		events.push("rhs_mutates");
		holder.value = 100;
		return 7;
	}
}

/** Mutable record-backed receiver used by the focused place fixture. */
class Holder {
	public var value:Int;

	public function new() {}
}

/** Int-backed abstract used to prove the first policy does not erase semantic identity. */
abstract WrappedInt(Int) from Int to Int {}

/** Record-backed control whose field must remain outside the primitive-Int slice. */
class AbstractHolder {
	public var value:WrappedInt;

	public function new() {}
}
