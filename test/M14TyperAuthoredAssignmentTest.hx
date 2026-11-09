import sys.io.File;

/**
	Checks that a value entering a written local type or a declared return type
	is accepted or rejected exactly where Haxe 4.3.7 does, with its message.

	Why
	- The typer accepted `var g:Float->Int = f` with `f:(Int)->Int`,
	  `function h(x:Int, y:Int):String return x + y;`, and `var x:Int = "s"`,
	  and the programs ran. Upstream rejects each one: `Float should be Int`,
	  `Int should be String`, `String should be Int` (haxe_ocaml-d3urc).

	What
	- `test/fixtures/typer_authored_assignment/cases.txt` lists one program per
	  line: `NEG|<upstream message>|<class Main body>|<other declarations>` or
	  `POS||...`. Upstream Haxe must reject each NEG program with that message and
	  accept each POS program. The hxhx typer, with the production standard-library
	  providers, must do the same.
	- Two same-shaped recursive typedefs must be accepted without exponential
	  work.
	- The POS lines guard against false rejections: function argument
	  contravariance and result covariance, Int widening to Float, Void results,
	  Dynamic, optional arguments, generic methods, abstracts with `from`/`to`
	  and `@:from`, enum abstracts, subclasses, interfaces, structures, and
	  nullable values.
**/
class M14TyperAuthoredAssignmentTest {
	static final root = ".tmp/m14_typer_authored_assignment";

	static function source(body:String, extra:String):String
		return "class Main { " + body + " }\n" + extra + "\n";

	/** Upstream's first diagnostic for the program, or "accepted". */
	static function upstream(program:String):String {
		File.saveContent(root + "/Main.hx", program);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--no-output", "-main", "Main", "--interp"]);
		final output = process.stderr.readAll().toString() + process.stdout.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code == 0)
			return "accepted";
		for (line in output.split("\n"))
			if (line.indexOf("Main.hx:") >= 0 && line.indexOf("Warning") < 0)
				return line;
		return output;
	}

	/** The hxhx typer's diagnostic for the program, or "accepted". */
	static function hxhx(program:String):String {
		try {
			M14Stage3RuntimeFixture.prepareProgram({source: program, path: root + "/Main.hx", root: root});
			return "accepted";
		} catch (error:Dynamic) {
			return Std.string(error);
		}
	}

	/**
		Two same-shaped recursive typedefs with different names reach the same type
		pairs through every recursive occurrence. Comparing them must take one visit
		per distinct pair: without that, five occurrences would need about 5^16 steps.
		The bound is far above the normal cost of typing this program.
	 */
	static function checkRecursiveTwinsStayFast(failures:Array<String>):Void {
		final program = source("static function s(a:Int->T, b:Int->T, c:Int->T, d:Int->T):T return s; "
			+ "static function main() { var direct:U = s; var local = s; var viaLocal:U = local; }",
			"typedef T = (Int->T, Int->T, Int->T, Int->T)->T; typedef U = (Int->U, Int->U, Int->U, Int->U)->U;");
		final oracle = upstream(program);
		if (oracle != "accepted")
			failures.push("upstream disagrees with the recursive twin program: " + oracle);
		final started = Sys.time();
		final actual = hxhx(program);
		final elapsed = Sys.time() - started;
		Sys.println("M14_TYPER_AUTHORED_ASSIGNMENT_RECURSIVE_TWINS seconds=" + Math.round(elapsed * 10) / 10);
		if (actual != "accepted")
			failures.push("false rejection of the recursive twin program: " + actual);
		if (elapsed > 30)
			failures.push("recursive twin typedefs took " + elapsed + " seconds");
	}

	static function main():Void {
		sys.FileSystem.createDirectory(root);
		final failures = new Array<String>();
		var count = 0;
		for (line in File.getContent("test/fixtures/typer_authored_assignment/cases.txt").split("\n")) {
			if (StringTools.trim(line).length == 0)
				continue;
			final parts = line.split("|");
			final kind = parts[0];
			final message = parts[1];
			final program = source(parts[2], parts.length > 3 ? parts[3] : "");
			final expectAccepted = kind == "POS";
			count++;
			final oracle = upstream(program);
			if (expectAccepted ? oracle != "accepted" : oracle.indexOf(message) < 0)
				failures.push("upstream disagrees with the case list: " + parts[2] + " -> " + oracle);
			final actual = hxhx(program);
			if (expectAccepted ? actual != "accepted" : actual.indexOf(message) < 0)
				failures.push((expectAccepted ? "false rejection: " : "missing or different rejection (want `" + message + "`): ")
					+ parts[2]
					+ " -> "
					+ actual);
		}
		checkRecursiveTwinsStayFast(failures);
		if (failures.length > 0)
			throw failures.join("\n");
		Sys.println("M14_TYPER_AUTHORED_ASSIGNMENT:PASS cases=" + count);
	}
}
