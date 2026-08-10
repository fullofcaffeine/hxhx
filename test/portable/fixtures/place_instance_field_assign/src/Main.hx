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

	static function boolRhs():Bool {
		events.push("bool_rhs");
		return true;
	}

	static function main():Void {
		Sys.println("initial=" + holder.value);
		final result = receiver().value = rhs();
		Sys.println("result=" + result + " final=" + holder.value + " events=" + events.join(",") + " abstract=" + abstractControl());

		events.resize(0);
		Sys.println("bool_initial=" + holder.ready);
		final boolResult = receiver().ready = boolRhs();
		Sys.println("bool_result=" + boolResult + " final=" + holder.ready + " events=" + events.join(","));
		Sys.println("nullable_initial=" + (holder.optionalCount == null) + "/" + (holder.optionalFlag == null));

		events.resize(0);
		final compoundResult = receiver().value += rhsMutating();
		Sys.println("compound=" + compoundResult + " final=" + holder.value + " events=" + events.join(","));

		events.resize(0);
		final postfixResult = receiver().value++;
		Sys.println("postfix=" + postfixResult + " final=" + holder.value + " events=" + events.join(","));

		events.resize(0);
		final prefixResult = ++receiver().value;
		Sys.println("prefix=" + prefixResult + " final=" + holder.value + " events=" + events.join(","));

		events.resize(0);
		final postfixDecrementResult = receiver().value--;
		Sys.println("postfix_decrement=" + postfixDecrementResult + " final=" + holder.value + " events=" + events.join(","));

		events.resize(0);
		final prefixDecrementResult = --receiver().value;
		Sys.println("prefix_decrement=" + prefixDecrementResult + " final=" + holder.value + " events=" + events.join(","));

		holder.value = 2147483647;
		final overflowResult = holder.value++;
		Sys.println("overflow=" + overflowResult + " final=" + holder.value);

		final concatCounter = new ConcatCounter();
		Sys.println(concatCounter.nextLabel());
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
	public var ready:Bool;
	public var optionalCount:Null<Int>;
	public var optionalFlag:Null<Bool>;

	public function new() {}
}

/** Regression control for a field update nested inside string concatenation. */
class ConcatCounter {
	var nextId:Int = 0;

	public function new() {}

	public function nextLabel():String {
		return "concat=" + nextId++;
	}
}

/** Int-backed abstract used to prove the first policy does not erase semantic identity. */
abstract WrappedInt(Int) from Int to Int {}

/** Record-backed control whose field must remain outside the primitive-Int slice. */
class AbstractHolder {
	public var value:WrappedInt;

	public function new() {}
}
