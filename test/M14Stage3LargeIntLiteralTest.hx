import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds integer literals around the signed 32-bit range with the Stage3
	native emitter and compares the program with upstream Haxe.

	Why
	- Upstream Haxe 4.3.7 types an unsuffixed decimal literal that does not fit
	  the signed 32-bit Int range as `Float`. The hxhx lexer turned such a
	  literal into `Int 0`, so `2147483648` and `-2147483649` both printed `0`
	  natively, and the build gave no error.

	What
	- `stage3_large_int_literals` prints values at both Int boundaries, beyond
	  them (with and without digit separators, and negated in parentheses),
	  arithmetic on the Float results, and 32-bit hexadecimal literals.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- A hexadecimal literal wider than 32 bits must be rejected, as upstream
	  rejects it with "Invalid hexadecimal integer".
	- An out-of-range integer switch pattern must be rejected by name until
	  HxParser has Float patterns (Bead haxe_ocaml-1rhgo).
**/
class M14Stage3LargeIntLiteralTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function compareWithUpstream(source:String, marker:String):Void {
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_large_int_literals_" + marker.toLowerCase();
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_LARGE_INT_LITERALS_" + marker + ":PASS");
	}

	/** Upstream's diagnostic for a rejected program, or null when it compiles. */
	static function upstreamDiagnostic(root:String):Null<String> {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		process.stdout.readAll();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		return status == 0 ? null : stderr;
	}

	/** Upstream Haxe and Stage3 must both reject `source`; Stage3's message must contain `stage3Text`. */
	static function rejectLikeUpstream(name:String, source:String, upstreamText:String, stage3Text:String):Void {
		final root = ".tmp/m14_stage3_large_int_literals_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		final upstream = upstreamDiagnostic(root);
		if (upstream == null || upstream.indexOf(upstreamText) < 0)
			throw name + ": upstream Haxe must reject the program with <" + upstreamText + ">, got: " + upstream;
		final message = try {
			final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
			null;
		} catch (error:haxe.Exception) {
			error.message;
		}
		deleteRecursive(root);
		if (message == null || message.indexOf(stage3Text) < 0)
			throw name + ": Stage3 must reject the program with <" + stage3Text + ">, got: " + message;
		Sys.println("M14_STAGE3_LARGE_INT_LITERALS_REJECT_" + name.toUpperCase() + ":PASS");
	}

	/**
		Check the parser's output for integer patterns outside the Int range. They must
		parse as Float constants (`2147483648` and `-2147483649` become `PFloat`), never as
		a wildcard that matches every value. `-2147483648` must fold to the minimum Int
		(`PInt`), as it does in expressions. This test does not run upstream; the native
		Float-pattern fixture compares these cases with upstream Haxe at run time.
	**/
	static function outOfRangePatterns():Void {
		function firstPattern(source:String):HxSwitchPattern {
			return switch HxParser.parseCompleteExprText(source) {
				case ESwitch(_, patterns, _): patterns[0];
				case other: throw "out_of_range_pattern: expected a switch, got " + Std.string(other);
			};
		}
		switch firstPattern("switch x { case 2147483648: 1; case _: 0; }") {
			case PFloat("2147483648.0"):
			case other:
				throw "out_of_range_pattern: 2147483648 must be the Float constant 2147483648.0, got " + Std.string(other);
		}
		switch firstPattern("switch x { case -2147483649: 1; case _: 0; }") {
			case PFloat("-2147483649.0"):
			case other:
				throw "out_of_range_pattern: -2147483649 must be the Float constant -2147483649.0, got " + Std.string(other);
		}
		switch firstPattern("switch x { case -2147483648: 1; case _: 0; }") {
			case PInt(value) if (value == -2147483647 - 1):
			case other:
				throw "out_of_range_pattern: -2147483648 must be the minimum Int, got " + Std.string(other);
		}
		Sys.println("M14_STAGE3_LARGE_INT_LITERALS_OUT_OF_RANGE_PATTERN:PASS");
	}

	static function requireEqual(actual:Null<Int>, expected:Null<Int>, label:String):Void {
		if (actual != expected)
			throw "literal_boundaries: " + label + " expected " + expected + ", got " + actual;
	}

	/**
		Classification at the lexer boundary, independent of the host's
		`Std.parseInt` (upstream Haxe 4.3.7 cases).
	**/
	static function literalBoundaries():Void {
		requireEqual(HxIntegerLiteral.decimal("2147483647"), 2147483647, "maximum Int");
		requireEqual(HxIntegerLiteral.decimal("2147483648"), null, "above maximum Int");
		requireEqual(HxIntegerLiteral.decimal("0000002147483647"), 2147483647, "leading zeros");
		requireEqual(HxIntegerLiteral.decimal("99999999999999999999"), null, "twenty digits");
		requireEqual(HxIntegerLiteral.decimal("12a"), null, "non-digit");
		requireEqual(HxIntegerLiteral.hexadecimal("0xFFFFFFFF"), -1, "32-bit hex");
		requireEqual(HxIntegerLiteral.hexadecimal("0x80000000"), -2147483647 - 1, "minimum Int bits");
		requireEqual(HxIntegerLiteral.hexadecimal("0x00000001"), 1, "eight hex digits with leading zeros");
		requireEqual(HxIntegerLiteral.hexadecimal("0x000000001"), null, "nine hex digits, as upstream rejects");
		requireEqual(HxIntegerLiteral.hexadecimal("0x100000000"), null, "wider than 32 bits");
		requireEqual(HxIntegerLiteral.hexadecimal("0x"), null, "no digits");
		final lexer = new HxLexer("0x100000000 2147483648 2147483647");
		final wide = lexer.next();
		if (!wide.kind.match(TInt(_)) || wide.numericText != "0x100000000")
			throw "literal_boundaries: the lexer must keep a wide hex literal's text for the parser to reject";
		final above = lexer.next();
		if (!above.kind.match(TFloat(_)) || above.numericText != "2147483648")
			throw "literal_boundaries: an out-of-range decimal must be a Float token that keeps its text";
		if (!lexer.next().kind.match(TInt(2147483647)))
			throw "literal_boundaries: the maximum Int must stay an Int token";
		Sys.println("M14_STAGE3_LARGE_INT_LITERALS_LITERAL_BOUNDARIES:PASS");
	}

	/** Upstream accepts a wide hex literal inside metadata arguments, which are not typed as values. */
	static function acceptWideHexInMetadata():Void {
		ParserStage.parse("class Main {\n\t@:foo(0x100000000) static function g() {}\n\n\tstatic function main() {}\n}\n", "Main.hx");
		Sys.println("M14_STAGE3_LARGE_INT_LITERALS_METADATA_WIDE_HEX:PASS");
	}

	static function main():Void {
		literalBoundaries();
		acceptWideHexInMetadata();
		outOfRangePatterns();
		rejectLikeUpstream("wide_hexadecimal", 'class Main {\n\tstatic function main() {\n\t\tvar x = 0x100000000;\n\t\tSys.println(x);\n\t}\n}\n',
			"Invalid hexadecimal integer", "Invalid hexadecimal integer");
		compareWithUpstream("test/fixtures/stage3_large_int_literals", "WHOLE_FILE");
	}
}
