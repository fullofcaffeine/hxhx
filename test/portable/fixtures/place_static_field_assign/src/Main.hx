/** Focused executable proof for value-producing mutable-static operations. */
class Main {
	static var localValue:Int = 10;
	static var floatValue:Float = 1.5;
	static final events:Array<String> = [];

	static function rhs(label:String, value:Int):Int {
		events.push(label);
		return value;
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
	}
}
