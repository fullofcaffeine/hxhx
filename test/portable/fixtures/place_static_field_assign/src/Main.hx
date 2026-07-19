/** Focused executable proof for value-producing mutable-static assignment. */
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
		final qualifiedResult = ExternalHolder.value = rhs("rhs_qualified", 9);
		Sys.println("qualified=" + qualifiedResult + " final=" + ExternalHolder.value + " events=" + events.join(","));

		events.resize(0);
		final qualifiedCompoundResult = ExternalHolder.value += rhsMutatingQualified();
		Sys.println("qualified_compound=" + qualifiedCompoundResult + " final=" + ExternalHolder.value + " events=" + events.join(","));

		floatValue += 0.5;
		Sys.println("float=" + floatValue);
	}
}
