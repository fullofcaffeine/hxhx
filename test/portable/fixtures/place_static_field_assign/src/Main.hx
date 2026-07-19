/** Focused executable proof for value-producing mutable-static assignment. */
class Main {
	static var localValue:Int = 10;
	static final events:Array<String> = [];

	static function rhs(label:String, value:Int):Int {
		events.push(label);
		return value;
	}

	static function main():Void {
		final localResult = localValue = rhs("rhs_local", 7);
		Sys.println("local=" + localResult + " final=" + localValue + " events=" + events.join(","));

		events.resize(0);
		final qualifiedResult = ExternalHolder.value = rhs("rhs_qualified", 9);
		Sys.println("qualified=" + qualifiedResult + " final=" + ExternalHolder.value + " events=" + events.join(","));
	}
}
