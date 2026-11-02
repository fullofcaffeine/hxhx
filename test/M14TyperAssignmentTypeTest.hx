import sys.io.File;

/**
	Checks the type that the hxhx typer gives an assignment used as a value
	against upstream Haxe 4.3.7.

	Why
	- Haxe types `place = value` as the type of `place`, after the value is
	  converted to it. `var ratio:Float = 0.5; (ratio = 5)` is a Float, and
	  `(maybe = 3)` with `maybe:Null<Int>` is a `Null<Int>`.
	- The hxhx typer gave an assignment to a local or an array element the
	  right-hand type (Int in both examples). Backends that read the recorded
	  type then converted the stored value the wrong way: native Stage3 emitted
	  `float_of_int` for a value that was already a Float.

	What
	- `typer_assignment_type/Main.hx` holds one `$type(...)` for each case:
	  locals, class fields, array elements, `Null<T>` destinations, an
	  abstract with `@:from`, and a compound assignment. Upstream prints each
	  type as a compile-time warning; `expected.types` lists them in order.
	- The test types the same program with hxhx (with each `$type(` replaced
	  by `(`) and compares the type of each assignment expression, in source
	  order, with that list.
	- `typer_assignment_type_null_local` assigns an Int to a local initialized
	  with bare `null` inside a call (`takeInt(n = 2)`). Upstream accepts it, and
	  hxhx must type it without rejecting the call.
**/
class M14TyperAssignmentTypeTest {
	static final fixture = "test/fixtures/typer_assignment_type";

	static function upstreamTypes():Array<String> {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", fixture, "-main", "Main", "--no-output", "--interp"]);
		final stderr = process.stderr.readAll().toString();
		process.stdout.readAll();
		process.exitCode();
		process.close();
		return [
			for (line in stderr.split("\n"))
				if (line.indexOf("Warning : ") >= 0) StringTools.trim(line.substr(line.indexOf("Warning : ") + "Warning : ".length))
		];
	}

	static function collect(expression:TypedExpr, types:Array<String>):Void {
		if (expression.getTag() == Assign || expression.getTag() == CompoundAssign)
			types.push(expression.getType().getDisplay());
		for (child in expression.getExpressions())
			collect(child, types);
	}

	static function collectStatement(statement:TypedStmt, types:Array<String>):Void {
		for (expression in statement.getExpressions())
			collect(expression, types);
		for (child in statement.getStatements())
			collectStatement(child, types);
	}

	static function main():Void {
		final expected = [
			for (line in File.getContent(fixture + "/expected.types").split("\n"))
				if (StringTools.trim(line).length > 0) StringTools.trim(line)
		];
		final upstream = upstreamTypes();
		if (upstream.join(",") != expected.join(","))
			throw "upstream assignment types changed: " + upstream.join(",") + " (expected " + expected.join(",") + ")";
		Sys.println("M14_TYPER_ASSIGNMENT_TYPE_UPSTREAM:PASS");

		final path = fixture + "/Main.hx";
		final source = StringTools.replace(File.getContent(path), "$type(", "(");
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: fixture});
		final actual = new Array<String>();
		for (typedClass in typed.getTypedClasses())
			if (typedClass.getSourceDeclaration().name == "Main")
				for (fn in typedClass.getFunctions())
					if (fn.getSourceDeclaration().name == "main")
						for (statement in fn.getBody().getStatements())
							collectStatement(statement, actual);
		if (actual.join(",") != expected.join(","))
			throw "hxhx assignment types differ from upstream:\n  hxhx:     " + actual.join(",") + "\n  upstream: " + expected.join(",");
		Sys.println("M14_TYPER_ASSIGNMENT_TYPE:PASS");
		acceptNullInitializedLocal();
	}

	/**
		A local initialized with bare `null` keeps the assigned value's type for
		the assignment, so `takeInt(n = 2)` is accepted as it is upstream.
	**/
	static function acceptNullInitializedLocal():Void {
		final source = "test/fixtures/typer_assignment_type_null_local";
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", source, "-main", "Main", "--no-output", "--interp"]);
		process.stdout.readAll();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "upstream rejected the null-initialized local program: " + stderr;
		final path = source + "/Main.hx";
		M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: source});
		Sys.println("M14_TYPER_ASSIGNMENT_TYPE_NULL_LOCAL:PASS");
	}
}
