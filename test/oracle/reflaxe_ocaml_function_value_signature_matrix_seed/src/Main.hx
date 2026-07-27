typedef MixedCallback = (flag:Bool, count:Int) -> String;
typedef ZeroCallback = () -> Bool;
typedef NullableIntCallback = (value:Null<Int>) -> Null<Int>;
typedef OptionalIntCallback = (?value:Int) -> Int;
typedef OptionalBoolCallback = (?value:Bool) -> Bool;
typedef EffectCallback = (value:String) -> Void;

/**
	Freezes represented function-value signatures and their evaluation order.

	Each case prints a small event ledger. A factory-produced callback must record
	`factory` before any source argument, while an omitted optional has no source
	event at all.
**/
class Main {
	static var events:Array<String> = [];

	static function record(event:String):Void {
		events.push(event);
	}

	static function reset():Void {
		events = [];
	}

	static function renderEvents():String {
		return events.join(",");
	}

	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function flag():Bool {
		record("flag");
		return true;
	}

	static function count():Int {
		record("count");
		return 2;
	}

	static function number():Int {
		record("number");
		return 7;
	}

	static function text():String {
		record("text");
		return "payload";
	}

	static function mixed(flag:Bool, count:Int):String {
		record("mixed");
		return (flag ? "yes:" : "no:") + count;
	}

	static function probe():Bool {
		record("probe");
		return true;
	}

	static function keepNullableInt(value:Null<Int>):Null<Int> {
		record("keep_nullable_int");
		return value;
	}

	static function optionalInt(?value:Int):Int {
		record("optional_int");
		return value == null ? -1 : value;
	}

	static function optionalBool(?value:Bool):Bool {
		record("optional_bool");
		return value == null ? false : value;
	}

	static function consumeText(value:String):Void {
		record("effect");
	}

	static function makeMixed():MixedCallback {
		record("factory");
		return mixed;
	}

	static function makeProbe():ZeroCallback {
		record("factory");
		return probe;
	}

	static function makeOptionalInt():OptionalIntCallback {
		record("factory");
		return optionalInt;
	}

	static function makeOptionalBool():OptionalBoolCallback {
		record("factory");
		return optionalBool;
	}

	static function makeEffect():EffectCallback {
		record("factory");
		return consumeText;
	}

	static function mixedLocalCase():Void {
		reset();
		final callback = mixed;
		final result = callback(flag(), count());
		printLine("mixed_local result=" + result + " events=" + renderEvents());
	}

	static function mixedFactoryCase():Void {
		reset();
		final result = makeMixed()(flag(), count());
		printLine("mixed_factory result=" + result + " events=" + renderEvents());
	}

	static function zeroLocalCase():Void {
		reset();
		final callback = probe;
		final result = callback();
		printLine("zero_local result=" + result + " events=" + renderEvents());
	}

	static function zeroFactoryCase():Void {
		reset();
		final result = makeProbe()();
		printLine("zero_factory result=" + result + " events=" + renderEvents());
	}

	static function nullableIntCase():Void {
		reset();
		final callback = keepNullableInt;
		final result = callback(number());
		printLine("nullable_int result=" + Std.string(result) + " events=" + renderEvents());
	}

	static function optionalIntOmittedCase():Void {
		reset();
		final callback = optionalInt;
		final result = callback();
		printLine("optional_int_omitted result=" + result + " events=" + renderEvents());
	}

	static function optionalIntFactorySuppliedCase():Void {
		reset();
		final result = makeOptionalInt()(number());
		printLine("optional_int_factory_supplied result=" + result + " events=" + renderEvents());
	}

	static function optionalBoolOmittedCase():Void {
		reset();
		final callback = optionalBool;
		final result = callback();
		printLine("optional_bool_omitted result=" + result + " events=" + renderEvents());
	}

	static function optionalBoolFactorySuppliedCase():Void {
		reset();
		final result = makeOptionalBool()(flag());
		printLine("optional_bool_factory_supplied result=" + result + " events=" + renderEvents());
	}

	static function effectLocalCase():Void {
		reset();
		final callback = consumeText;
		callback(text());
		printLine("effect_local events=" + renderEvents());
	}

	static function effectFactoryCase():Void {
		reset();
		makeEffect()(text());
		printLine("effect_factory events=" + renderEvents());
	}

	static function main():Void {
		mixedLocalCase();
		mixedFactoryCase();
		zeroLocalCase();
		zeroFactoryCase();
		nullableIntCase();
		optionalIntOmittedCase();
		optionalIntFactorySuppliedCase();
		optionalBoolOmittedCase();
		optionalBoolFactorySuppliedCase();
		effectLocalCase();
		effectFactoryCase();
	}
}
