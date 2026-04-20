import sys.FileSystem;
import sys.io.File;
import haxe.ds.StringMap;

class M14HxhxStage3ReceiverCallIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertEquals(actual:String, expected:String, message:String):Void {
		if (actual != expected)
			throw message + "\nexpected:\n" + expected + "\nactual:\n" + actual;
	}

	static function assertNotContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) >= 0)
			throw message + " (unexpected `" + needle + "`)";
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path)) {
				deleteRecursive(haxe.io.Path.join([path, entry]));
			}
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_hxhx_stage3_receiver_call_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		final src = [
			'class Main {',
			'  public function new() {}',
			'  function add(v:Int):Int {',
			'    return v + 1;',
			'  }',
			'  function callOn(other:Main, n:Int):Int {',
			'    return other.add(n);',
			'  }',
			'  static function main() {',
			'    var m = new Main();',
			'    Sys.println(Std.string(m.callOn(m, 41)));',
			'  }',
			'}',
		].join("\n");
		File.saveContent(mainHx, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, mainHx);
			final resolved = new ResolvedModule("Main", mainHx, parsed);
			final missingTypeAttempts = new Array<String>();
			final index = TyperIndex.build([resolved]);
			final loader = new ModuleLoader([srcDir], new StringMap<String>(), index, function(typePath:String):Bool {
				missingTypeAttempts.push(typePath);
				return false;
			});
			loader.markResolvedAlready([resolved]);
			TyperStage.typeResolvedModule(resolved, index, loader);
			assertTrue(missingTypeAttempts.indexOf("m") < 0, 'Stage3 typer treated lower-case receiver `m` as a type path.');
			assertTrue(missingTypeAttempts.indexOf("other") < 0, 'Stage3 typer treated lower-case receiver `other` as a type path.');

			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			final exePath = EmitterStage.emitToDir(expanded, outDir, true);
			assertTrue(FileSystem.exists(exePath), 'Emitter did not produce executable: ' + exePath);

			var mainMl:Null<String> = null;
			for (entry in FileSystem.readDirectory(outDir)) {
				if (entry == 'Main.ml' || entry == 'main.ml' || StringTools.endsWith(entry, '__Main.ml')) {
					mainMl = haxe.io.Path.join([outDir, entry]);
					break;
				}
			}
			if (mainMl == null) {
				throw 'Stage3 output missing main module (`Main.ml` or `*__Main.ml`); outDir entries: ' + FileSystem.readDirectory(outDir).join(',');
			}

			final ocaml = File.getContent(mainMl);
			assertTrue(ocaml.indexOf('add (other) (n)') >= 0, 'Stage3 receiver-call emit missing `add (other) (n)` call shape.');
			assertTrue(ocaml.indexOf('add (this_) (other) (n)') < 0, 'Stage3 receiver-call regression: emitted over-applied `add (this_) (other) (n)`.');

			final resolvedOverloadHx = haxe.io.Path.join([srcDir, 'OverloadResolved.hx']);
			final resolvedOverloadSrc = [
				'extern class ResolvedTool {',
				'  overload static function label(v:Int):String;',
				'  overload static function label(v:String):String;',
				'}',
				'class OverloadResolved {',
				'  static function main() {',
				'    ResolvedTool.label(12);',
				'    ResolvedTool.label("x");',
				'  }',
				'}',
			].join("\n");
			File.saveContent(resolvedOverloadHx, resolvedOverloadSrc);
			final resolvedOverloadParsed = ParserStage.parse(resolvedOverloadSrc, resolvedOverloadHx);
			final resolvedOverloadResolved = new ResolvedModule("OverloadResolved", resolvedOverloadHx, resolvedOverloadParsed);
			final resolvedOverloadIndex = TyperIndex.build([resolvedOverloadResolved]);
			final resolvedOverloadLoader = new ModuleLoader([srcDir], new StringMap<String>(), resolvedOverloadIndex, function(_typePath:String):Bool {
				return false;
			});
			resolvedOverloadLoader.markResolvedAlready([resolvedOverloadResolved]);
			TyperStage.typeResolvedModule(resolvedOverloadResolved, resolvedOverloadIndex, resolvedOverloadLoader);

			final overloadHx = haxe.io.Path.join([srcDir, 'OverloadAmbiguous.hx']);
			final overloadSrc = [
				'extern class ToolCache {',
				'  overload static function extractTar(?flags:Array<String>):Void;',
				'  overload static function extractTar(?flags:String):Void;',
				'}',
				'class OverloadAmbiguous {',
				'  static function main() {',
				'    ToolCache.extractTar();',
				'  }',
				'}',
			].join("\n");
			File.saveContent(overloadHx, overloadSrc);
			final overloadParsed = ParserStage.parse(overloadSrc, overloadHx);
			final overloadResolved = new ResolvedModule("OverloadAmbiguous", overloadHx, overloadParsed);
			final overloadIndex = TyperIndex.build([overloadResolved]);
			final overloadLoader = new ModuleLoader([srcDir], new StringMap<String>(), overloadIndex, function(_typePath:String):Bool {
				return false;
			});
			overloadLoader.markResolvedAlready([overloadResolved]);
			var overloadFailure:Null<String> = null;
			try {
				TyperStage.typeResolvedModule(overloadResolved, overloadIndex, overloadLoader);
			} catch (e:TyperError) {
				overloadFailure = e.getMessage();
			}
			assertTrue(overloadFailure != null, 'Stage3 typer accepted an ambiguous zero-arg overload call.');
			final overloadDiagnostic = TyperStage.extractRawDiagnostic(overloadFailure);
			assertTrue(overloadDiagnostic != null, 'Ambiguous overload should surface as a Haxe-style raw diagnostic.');
			assertTrue(overloadFailure.indexOf('Ambiguous overload, candidates follow') >= 0, 'Ambiguous overload diagnostic missing headline.');
			assertTrue(overloadFailure.indexOf('(?flags : Null<Array<String>>) -> Void') >= 0, 'Ambiguous overload diagnostic missing Array candidate.');
			assertTrue(overloadFailure.indexOf('(?flags : Null<String>) -> Void') >= 0, 'Ambiguous overload diagnostic missing String candidate.');

			final upstream437OverloadHx = haxe.io.Path.join([srcDir, 'Main.hx']);
			final upstream437OverloadSrc = [
				'extern class ToolCache {',
				'\toverload static function extractTar(?flags:Array<String>):Void;',
				'\toverload static function extractTar(?flags:String):Void;',
				'}',
				'',
				'class Main {',
				'\tstatic function main() {',
				'\t\tToolCache.extractTar();',
				'\t}',
				'}',
			].join("\n");
			File.saveContent(upstream437OverloadHx, upstream437OverloadSrc);
			final upstream437OverloadParsed = ParserStage.parse(upstream437OverloadSrc, upstream437OverloadHx);
			final upstream437OverloadResolved = new ResolvedModule("Main", upstream437OverloadHx, upstream437OverloadParsed);
			final upstream437OverloadIndex = TyperIndex.build([upstream437OverloadResolved]);
			final upstream437OverloadLoader = new ModuleLoader([srcDir], new StringMap<String>(), upstream437OverloadIndex, function(_typePath:String):Bool {
				return false;
			});
			upstream437OverloadLoader.markResolvedAlready([upstream437OverloadResolved]);
			var upstream437Failure:Null<String> = null;
			try {
				TyperStage.typeResolvedModule(upstream437OverloadResolved, upstream437OverloadIndex, upstream437OverloadLoader);
			} catch (e:TyperError) {
				upstream437Failure = e.getMessage();
			}
			final upstream437Diagnostic = TyperStage.extractRawDiagnostic(upstream437Failure);
			assertEquals(upstream437Diagnostic, [
				'Main.hx:3: characters 2-57 : Ambiguous overload, candidates follow',
				'Main.hx:0: characters 1-11 : ... (?flags : Null<Array<String>>) -> Void',
				'Main.hx:0: characters 1-11 : ... (?flags : Null<String>) -> Void',
			].join("\n"),
				'Ambiguous overload diagnostic should match Haxe 4.3.7 Issue10434 expected stderr.');

			final vectorOutDir = haxe.io.Path.join([tmpRoot, 'vector_out']);
			final vectorLengthArg = new HxFunctionArg("length", "Int", HxDefaultValue.NoDefault);
			final vectorArrayArg = new HxFunctionArg("array", "Array<Dynamic>", HxDefaultValue.NoDefault);
			final vectorLocalR = new HxFieldDecl("r", HxVisibility.Public, true, "Dynamic", HxExpr.ENew("haxe.ds.Vector", [HxExpr.EIdent("length")]));
			final vectorLocalLen = new HxFieldDecl("len", HxVisibility.Public, true, "Int", HxExpr.EIdent("length"));
			final vectorClass = new HxClassDecl("Vector", false, [
				new HxFunctionDecl("new", HxVisibility.Public, false, [vectorLengthArg], "Void", [], ""),
				new HxFunctionDecl("fromArrayCopy", HxVisibility.Public, true, [vectorArrayArg], "haxe.ds.Vector<Dynamic>",
					[HxStmt.SReturn(HxExpr.EIdent("array"), HxPos.unknown())], "")
			], [vectorLocalR, vectorLocalLen]);
			final vectorDecl = new HxModuleDecl("haxe.ds", [], vectorClass, [vectorClass], false, false);
			final vectorTyped = TyperStage.typeModule(new ParsedModule("", vectorDecl, "haxe/ds/Vector.hx"));
			EmitterStage.emitToDir(new MacroExpandedProgram([vectorTyped], false), vectorOutDir, true, false);
			final vectorMl = File.getContent(haxe.io.Path.join([vectorOutDir, "Haxe_ds_Vector.ml"]));
			assertNotContains(vectorMl, "let r =", "Stage3 OCaml should not emit haxe.ds.Vector scanned local `r` as a static field.");
			assertNotContains(vectorMl, "let len =", "Stage3 OCaml should not emit haxe.ds.Vector scanned local `len` as a static field.");
			assertNotContains(vectorMl, "new_ (__hx_obj)", "Stage3 OCaml should not emit Vector local initialization that calls an unbound constructor.");
		} catch (e:Dynamic) {
			thrown = e;
		}

		if (thrown != null) {
			Sys.println('debug_out=' + tmpRoot);
			throw thrown;
		}
		deleteRecursive(tmpRoot);
	}
}
