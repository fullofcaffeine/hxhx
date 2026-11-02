import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds constant switch patterns with the Stage3 native emitter and compares
	the program with upstream Haxe.

	Why
	- HxParser had no Float pattern. `case 1.5:` fell through to a best-effort
	  branch that consumed one token and returned a wildcard, so the case
	  matched every value. A negative constant such as `case -1:` took the
	  same branch, and so did any other token, for example a regular
	  expression literal, which upstream rejects.

	What
	- `stage3_float_patterns` covers Float constants (negative, exponent, and
	  leading-dot spellings), Int constants in a Float switch, mixed Int and
	  Float or-patterns, guards (including a guard that fails before an equal
	  later constant), negative Int constants, and String, Bool and null
	  constants. The native executable must print exactly what upstream Haxe
	  4.3.7 prints.
	- The parser must produce exact patterns for these constants and reject
	  an unrecognized pattern by name, as upstream does.
**/
class M14Stage3FloatPatternTest {
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
		final outDir = ".tmp/m14_stage3_float_patterns_" + marker.toLowerCase();
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_FLOAT_PATTERNS_" + marker + ":PASS");
	}

	static function patterns(source:String):Array<HxSwitchPattern> {
		return switch HxParser.parseCompleteExprText(source) {
			case ESwitch(_, patterns, _): patterns;
			case other: throw "expected a switch, got " + other;
		};
	}

	/** Each constant must parse into its exact pattern, never a wildcard. */
	static function parsedConstants():Void {
		final expected = [
			"switch x { case 1.5: 0; }" => "PFloat(1.5)",
			"switch x { case -2.5: 0; }" => "PFloat(-2.5)",
			"switch x { case 1e3: 0; }" => "PFloat(1e3)",
			"switch x { case .5: 0; }" => "PFloat(0.5)",
			"switch x { case -1: 0; }" => "PInt(-1)",
			"switch x { case 7 | 8.5: 0; }" => "POr([PInt(7),PFloat(8.5)])",
			"switch x { case \"a\": 0; }" => "PString(a)",
			"switch x { case true: 0; }" => "PBool(true)",
			"switch x { case null: 0; }" => "PNull",
		];
		for (source => shape in expected) {
			final actual = Std.string(patterns(source)[0]);
			if (actual != shape)
				throw "parsed_constants: " + source + " must parse as " + shape + ", got " + actual;
		}
		Sys.println("M14_STAGE3_FLOAT_PATTERNS_PARSED_CONSTANTS:PASS");
	}

	/** Upstream rejects a regular expression literal as a pattern ("Unrecognized pattern: ~/a/"). */
	static function rejectUnrecognizedPattern():Void {
		final message = try {
			patterns("switch s { case ~/a/: 1; case _: 0; }");
			null;
		} catch (error:haxe.Exception) {
			error.message;
		}
		if (message == null || message.indexOf("Unrecognized pattern: ~/a/") < 0)
			throw "unrecognized_pattern: the parser must reject a regex pattern by name, got: " + message;
		Sys.println("M14_STAGE3_FLOAT_PATTERNS_REJECT_UNRECOGNIZED:PASS");
	}

	static function main():Void {
		parsedConstants();
		rejectUnrecognizedPattern();
		compareWithUpstream("test/fixtures/stage3_float_patterns", "WHOLE_FILE");
	}
}
