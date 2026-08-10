/** Focused executable proof for value-producing mutable-static operations. */
class Main {
	static var localValue:Int = 10;
	static var floatValue:Float = 1.5;
	static final events:Array<String> = [];
	public static var sameModuleValue:Int = 20;
	public static var sameModuleBool:Bool;
	public static var sameModuleNullableInt:Null<Int>;
	public static var sameModuleObject:SameModuleWorker;

	static function rhs(label:String, value:Int):Int {
		events.push(label);
		return value;
	}

	static function rhsBool():Bool {
		events.push("rhs_bool");
		return true;
	}

	static function rhsMutatingLocal():Int {
		events.push("rhs_mutates_local");
		localValue = 100;
		return 3;
	}

	static function rhsMutatingQualified():Int {
		events.push("rhs_mutates_qualified");
		ExternalHolder.value = 100;
		return 3;
	}

	static function main():Void {
		Sys.println(SameModuleWorker.run());
		Sys.println("omitted=" + ExternalHolder.omitted);
		Sys.println("omitted_bool=" + ExternalHolder.omittedBool);
		Sys.println("omitted_nullable=" + (ExternalHolder.omittedNullableInt == null) + "/" + (ExternalHolder.omittedNullableBool == null));
		Sys.println("omitted_string=" + (ExternalHolder.omittedString == null));
		final boolResult = ExternalHolder.omittedBool = rhsBool();
		Sys.println("bool=" + boolResult + " final=" + ExternalHolder.omittedBool + " events=" + events.join(","));
		final stringResult = ExternalHolder.omittedString = "written";
		Sys.println("string=" + stringResult + " final=" + ExternalHolder.omittedString);

		events.resize(0);
		final localResult = localValue = rhs("rhs_local", 7);
		Sys.println("local=" + localResult + " final=" + localValue + " events=" + events.join(","));

		events.resize(0);
		final localCompoundResult = localValue += rhsMutatingLocal();
		Sys.println("local_compound=" + localCompoundResult + " final=" + localValue + " events=" + events.join(","));

		events.resize(0);
		final localPostfixResult = localValue++;
		Sys.println("local_postfix=" + localPostfixResult + " final=" + localValue + " events=" + events.join(","));
		final localPrefixResult = ++localValue;
		Sys.println("local_prefix=" + localPrefixResult + " final=" + localValue + " events=" + events.join(","));
		final localPostfixDecrementResult = localValue--;
		Sys.println("local_postfix_decrement=" + localPostfixDecrementResult + " final=" + localValue + " events=" + events.join(","));
		final localPrefixDecrementResult = --localValue;
		Sys.println("local_prefix_decrement=" + localPrefixDecrementResult + " final=" + localValue + " events=" + events.join(","));

		events.resize(0);
		final qualifiedResult = ExternalHolder.value = rhs("rhs_qualified", 9);
		Sys.println("qualified=" + qualifiedResult + " final=" + ExternalHolder.value + " events=" + events.join(","));

		events.resize(0);
		final qualifiedCompoundResult = ExternalHolder.value += rhsMutatingQualified();
		Sys.println("qualified_compound=" + qualifiedCompoundResult + " final=" + ExternalHolder.value + " events=" + events.join(","));

		events.resize(0);
		final qualifiedPostfixResult = ExternalHolder.value++;
		Sys.println("qualified_postfix=" + qualifiedPostfixResult + " final=" + ExternalHolder.value + " events=" + events.join(","));
		final qualifiedPrefixResult = ++ExternalHolder.value;
		Sys.println("qualified_prefix=" + qualifiedPrefixResult + " final=" + ExternalHolder.value + " events=" + events.join(","));
		final qualifiedPostfixDecrementResult = ExternalHolder.value--;
		Sys.println("qualified_postfix_decrement="
			+ qualifiedPostfixDecrementResult
			+ " final="
			+ ExternalHolder.value
			+ " events="
			+ events.join(","));
		final qualifiedPrefixDecrementResult = --ExternalHolder.value;
		Sys.println("qualified_prefix_decrement="
			+ qualifiedPrefixDecrementResult
			+ " final="
			+ ExternalHolder.value
			+ " events="
			+ events.join(","));

		floatValue += 0.5;
		Sys.println("float=" + floatValue);
		final floatPostfixResult = floatValue++;
		Sys.println("float_postfix=" + floatPostfixResult + " final=" + floatValue);

		final mapped = [1, 2, 3].map(value -> value + 0.5);
		final filtered = [1, 2, 3, 4].filter(value -> value % 2 == 0);
		Sys.println("mapped=" + mapped.join(",") + " filtered=" + filtered.join(","));
	}
}

/**
	Non-primary type emitted before `Main` in the same OCaml compilation unit.

	Its methods access storage owned by the later primary type, which proves that
	the target declares shared static cells before either type's value bindings.
**/
class SameModuleWorker {
	public function new() {}

	public static function run():String {
		final assigned = Main.sameModuleValue = 21;
		final compound = Main.sameModuleValue += 2;
		final postfix = Main.sameModuleValue++;
		final prefix = ++Main.sameModuleValue;
		final object = new SameModuleWorker();
		Main.sameModuleObject = object;
		final sameObject = Main.sameModuleObject == object;
		final boolAssigned = Main.sameModuleBool = true;
		final nullableDefault = Main.sameModuleNullableInt == null;
		return 'same_module=$assigned/$compound/$postfix/$prefix/${Main.sameModuleValue}/$sameObject/$boolAssigned/${Main.sameModuleBool}/$nullableDefault';
	}
}
