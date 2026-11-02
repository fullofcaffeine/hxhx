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
		if (failures.length > 0)
			throw failures.join("\n");
		Sys.println("M14_TYPER_AUTHORED_ASSIGNMENT:PASS cases=" + count);
	}
}
