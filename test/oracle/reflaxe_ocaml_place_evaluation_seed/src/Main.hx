/**
	Freezes Haxe evaluation order and assignment-result behavior for mutable
	places. The same source is run through the upstream oracle and reflaxe.ocaml.
**/
class Main {
	static var holder = new PlaceHolder();
	static var values:Array<Int> = [10, 20];
	static var dynamicValue:Dynamic = {value: 10};
	static var staticValue = 10;

	static function reset():Void {
		EventLog.reset();
		holder.reset(10, 10);
		values = [10, 20];
		dynamicValue = {value: 10};
		staticValue = 10;
	}

	static function receiver():PlaceHolder {
		EventLog.record("receiver");
		return holder;
	}

	static function arrayReceiver():Array<Int> {
		EventLog.record("array");
		return values;
	}

	static function dynamicReceiver():Dynamic {
		EventLog.record("dynamic");
		return dynamicValue;
	}

	static function index():Int {
		EventLog.record("index");
		return 1;
	}

	static function rhs(value:Int):Int {
		EventLog.record("rhs");
		return value;
	}

	static function rhsMutatingField(value:Int):Int {
		EventLog.record("rhs_mutates");
		holder.field = 100;
		return value;
	}

	static function rhsMutatingStatic(value:Int):Int {
		EventLog.record("rhs_mutates_static");
		staticValue = 100;
		return value;
	}

	static function rhsMutatingArray(value:Int):Int {
		EventLog.record("rhs_mutates_array");
		values[1] = 100;
		return value;
	}

	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function show(label:String, result:Int, finalValue:Int):Void {
		printLine(label + " result=" + result + " final=" + finalValue + " events=" + EventLog.render());
	}

	static function showDynamic(label:String, result:Dynamic, finalValue:Dynamic):Void {
		printLine(label + " result=" + result + " final=" + finalValue + " events=" + EventLog.render());
	}

	static function localCases():Void {
		reset();
		var value = 10;
		final assignResult = value = rhs(7);
		show("local_assign", assignResult, value);

		reset();
		var value = 10;
		final compoundResult = value += rhs(3);
		show("local_compound", compoundResult, value);

		reset();
		var value = 10;
		final postfixResult = value++;
		show("local_postfix", postfixResult, value);

		reset();
		var value = 10;
		final prefixResult = ++value;
		show("local_prefix", prefixResult, value);
	}

	static function staticCases():Void {
		reset();
		final assignResult = staticValue = rhs(7);
		show("static_assign", assignResult, staticValue);

		reset();
		final compoundResult = staticValue += rhs(3);
		show("static_compound", compoundResult, staticValue);

		reset();
		final mutatingRhsResult = staticValue += rhsMutatingStatic(3);
		show("static_compound_rhs_mutates", mutatingRhsResult, staticValue);

		reset();
		final postfixResult = staticValue++;
		show("static_postfix", postfixResult, staticValue);

		reset();
		final prefixResult = ++staticValue;
		show("static_prefix", prefixResult, staticValue);

		reset();
		final postfixDecrementResult = staticValue--;
		show("static_postfix_decrement", postfixDecrementResult, staticValue);

		reset();
		final prefixDecrementResult = --staticValue;
		show("static_prefix_decrement", prefixDecrementResult, staticValue);
	}

	static function fieldCases():Void {
		reset();
		final assignResult = receiver().field = rhs(7);
		show("field_assign", assignResult, holder.field);

		reset();
		final compoundResult = receiver().field += rhs(3);
		show("field_compound", compoundResult, holder.field);

		reset();
		final mutatingRhsResult = receiver().field += rhsMutatingField(3);
		show("field_compound_rhs_mutates", mutatingRhsResult, holder.field);

		reset();
		final postfixResult = receiver().field++;
		show("field_postfix", postfixResult, holder.field);

		reset();
		final prefixResult = ++receiver().field;
		show("field_prefix", prefixResult, holder.field);
	}

	static function propertyCases():Void {
		reset();
		final assignResult = receiver().property = rhs(7);
		show("property_assign", assignResult, holder.rawProperty());

		reset();
		final compoundResult = receiver().property += rhs(3);
		show("property_compound", compoundResult, holder.rawProperty());

		reset();
		final postfixResult = receiver().property++;
		show("property_postfix", postfixResult, holder.rawProperty());

		reset();
		final prefixResult = ++receiver().property;
		show("property_prefix", prefixResult, holder.rawProperty());
	}

	static function arrayCases():Void {
		reset();
		final assignResult = arrayReceiver()[index()] = rhs(7);
		show("array_assign", assignResult, values[1]);

		reset();
		final compoundResult = arrayReceiver()[index()] += rhs(3);
		show("array_compound", compoundResult, values[1]);

		reset();
		final mutatingRhsResult = arrayReceiver()[index()] += rhsMutatingArray(3);
		show("array_compound_rhs_mutates", mutatingRhsResult, values[1]);

		reset();
		final postfixResult = arrayReceiver()[index()]++;
		show("array_postfix", postfixResult, values[1]);

		reset();
		final prefixResult = ++arrayReceiver()[index()];
		show("array_prefix", prefixResult, values[1]);
	}

	static function dynamicCases():Void {
		reset();
		final assignResult:Int = dynamicReceiver().value = rhs(7);
		showDynamic("dynamic_assign", assignResult, dynamicValue.value);

		reset();
		final compoundResult:Int = dynamicReceiver().value += rhs(3);
		showDynamic("dynamic_compound", compoundResult, dynamicValue.value);

		reset();
		final postfixResult:Dynamic = dynamicReceiver().value++;
		showDynamic("dynamic_postfix", postfixResult, dynamicValue.value);

		reset();
		final prefixResult:Dynamic = ++dynamicReceiver().value;
		showDynamic("dynamic_prefix", prefixResult, dynamicValue.value);
	}

	static function main():Void {
		localCases();
		staticCases();
		fieldCases();
		propertyCases();
		arrayCases();
		dynamicCases();
	}
}
