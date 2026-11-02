import sys.FileSystem;

/**
	Unbraced `try` bodies and handlers keep every catch clause.

	Why
	- The statement parser read an unbraced try body with the caller's stop
	  rule. Statement recovery then skipped every token up to the next `;`,
	  including `catch (e:String) handler`, so
	  `try f() catch (e:String) g();` ran `f()` with no handler at all. A
	  thrown value escaped on every route, and an unbraced handler body could
	  leak out as a plain statement.

	What
	- The parse check requires the handlers to stay attached and the next
	  statement to stay outside the try. It also requires `try f(); catch ...`
	  to be rejected, as upstream does.
	- `unbraced_try_catch` uses unbraced try bodies and handlers as
	  statements, with one and several catches, in if/else branches and loop
	  bodies, as values, and nested. Upstream Haxe 4.3.7, the JavaScript route,
	  and the Stage3 native route must print the same text.
**/
class M14UnbracedTryCatchTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function body(source:String):Array<HxStmt> {
		final parsed = ParserStage.parse("class Main {\n\tstatic function main():Void {\n" + source + "\n\t}\n}\n", "Main.hx");
		return HxFunctionDecl.getBody(HxClassDecl.getFunctions(HxModuleDecl.getClasses(parsed.getDecl())[0])[0]);
	}

	/** The parsed shape must keep every handler attached and leave the next statement outside. */
	static function checkParse():Void {
		final statements = body("try a() catch (e:String) b() catch (e:Int) c(); d();");
		if (statements.length != 2)
			throw "unbraced try must stay one statement followed by d(): " + statements.length;
		switch statements[0] {
			case STry(tryBody, catches, _):
				if (catches.length != 2 || catches[0].typeHint != "String" || catches[1].typeHint != "Int")
					throw "unbraced try lost a catch clause: " + catches.length;
				if (tryBody.match(SBlock(_, _)))
					throw "unbraced try body became a block";
			case other:
				throw "unbraced try did not parse as a try statement: " + other;
		}
		var rejected:Null<String> = null;
		try {
			body("try a(); catch (e:String) b();");
		} catch (error:Dynamic) {
			rejected = Std.string(error);
		}
		// Upstream Haxe 4.3.7 also rejects this program: the `;` ends the statement.
		if (rejected == null || rejected.indexOf("Unexpected catch") < 0)
			throw "a try body ending with ';' before catch must be rejected: " + rejected;
		Sys.println("M14_UNBRACED_TRY_CATCH_PARSE:PASS");
	}

	static function main():Void {
		checkParse();
		final source = "test/fixtures/unbraced_try_catch";
		final path = source + "/Main.hx";
		final expected = sys.io.File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final text = sys.io.File.getContent(path);
		JsRuntimeFixture.assertRuntime(M14Stage3RuntimeFixture.prepareMain({source: text, path: path, root: source}), "Main", expected);
		Sys.println("M14_UNBRACED_TRY_CATCH_JS:PASS");
		final outDir = ".tmp/m14_unbraced_try_catch";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: text, path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_UNBRACED_TRY_CATCH_STAGE3:PASS");
	}
}
