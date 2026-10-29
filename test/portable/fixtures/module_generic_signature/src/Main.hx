/** Observes concrete results, reference identity, nested state and cleanup on failure. */
class Main {
	static function main():Void {
		final scope = new Scope();
		Sys.println(First.number(scope, 41));
		Sys.println(First.text(scope));
		Sys.println(First.flag(scope, true));
		final values = [1];
		final returned = First.values(scope, values);
		returned.push(2);
		Sys.println(values.join(","));
		Sys.println(returned == values);
		Sys.println(First.missing(scope) == null);
		Sys.println(First.nested(scope));
		Sys.println(scope.active);
		var caught = false;
		try {
			First.failing(scope);
		} catch (error:Dynamic) {
			// The test observes the deliberately thrown String at this exception boundary.
			caught = error == "boom";
		}
		Sys.println(caught);
		Sys.println(scope.active);
		Sys.println(scope.entries);
		Sys.println(First.evaluation(scope));
		Sys.println(First.number(scope, -1) == 0);
		Sys.println(!First.flag(scope, false));
		Sys.println(First.nullableNumber(scope, null) == null);
		Sys.println(First.nullableNumber(scope, 0) == 0);
		Sys.println(First.nullableNumber(scope, 7) == 7);
		Sys.println(First.nullableFlag(scope, null) == null);
		Sys.println(First.nullableFlag(scope, false) == false);
		Sys.println(First.nullableFlag(scope, true) == true);
		Sys.println(First.nullableFlag(scope, First.nullableFlag(scope, false)) == false);
		Sys.println(First.nullableFlag(scope, First.nullableFlag(scope, null)) == null);
		Sys.println(First.describeNullableFlag(scope, null));
		Sys.println(First.describeNullableFlag(scope, false));
		Sys.println(First.describeNullableFlag(scope, true));
	}
}
