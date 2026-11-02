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
		HxParser has no Float switch pattern yet (Bead haxe_ocaml-1rhgo). An
		out-of-range integer pattern is a Float constant, so it must be rejected
		by name rather than parsed as a wildcard that matches every value.
	**/
	static function rejectOutOfRangePattern():Void {
		final message = try {
			HxParser.parseCompleteExprText("switch x { case 2147483648: 1; case _: 0; }");
			null;
		} catch (error:haxe.Exception) {
			error.message;
		}
		if (message == null || message.indexOf("Float constant patterns are not supported yet: 2147483648") < 0)
			throw "out_of_range_pattern: the parser must reject the pattern by name, got: " + message;
		Sys.println("M14_STAGE3_LARGE_INT_LITERALS_REJECT_OUT_OF_RANGE_PATTERN:PASS");
	}

	static function main():Void {
		rejectOutOfRangePattern();
		rejectLikeUpstream("wide_hexadecimal", 'class Main {\n\tstatic function main() {\n\t\tvar x = 0x100000000;\n\t\tSys.println(x);\n\t}\n}\n',
			"Invalid hexadecimal integer", "Invalid hexadecimal integer");
		compareWithUpstream("test/fixtures/stage3_large_int_literals", "WHOLE_FILE");
	}
}
