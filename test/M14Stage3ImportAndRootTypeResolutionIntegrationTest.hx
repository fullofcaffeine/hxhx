import sys.FileSystem;
import sys.io.File;

class M14Stage3ImportAndRootTypeResolutionIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
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
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_import_and_root_type_resolution_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		final haxeSrcDir = haxe.io.Path.join([tmpRoot, 'src_haxe']);
		final haxeOutDir = haxe.io.Path.join([tmpRoot, 'out_haxe']);
		final phpSrcDir = haxe.io.Path.join([tmpRoot, 'src_php']);
		final phpOutDir = haxe.io.Path.join([tmpRoot, 'out_php']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);
		FileSystem.createDirectory(haxeSrcDir);
		FileSystem.createDirectory(phpSrcDir);
		FileSystem.createDirectory(haxe.io.Path.join([srcDir, 'utest']));
		FileSystem.createDirectory(haxe.io.Path.join([srcDir, 'php']));
		FileSystem.createDirectory(haxe.io.Path.join([haxeSrcDir, 'haxe']));
		FileSystem.createDirectory(haxe.io.Path.join([phpSrcDir, 'php']));

		final assertHx = haxe.io.Path.join([srcDir, 'utest', 'Assert.hx']);
		File.saveContent(assertHx, [
			'package utest;',
			'class Assert {',
			'  public static function contains(v:Dynamic, values:Dynamic, pos:Dynamic):Bool {',
			'    return true;',
			'  }',
			'}',
		].join("\n"));

		final phpSyntaxHx = haxe.io.Path.join([srcDir, 'php', 'Syntax.hx']);
		File.saveContent(phpSyntaxHx, [
			'package php;',
			'extern class Syntax {',
			'  static function code(code:String, args:haxe.Rest<Dynamic>):Dynamic;',
			'}',
		].join("\n"));

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		final src = [
			'package unit;',
			'import haxe.CallStack;',
			'import utest.Assert;',
			'extern class RestExtern {',
			'  static function code(code:String, args:haxe.Rest<Dynamic>):Dynamic;',
			'  static function coalesce<T>(left:T, right:T):T;',
			'}',
			'class Main {',
			'  static function render():String {',
			'    return CallStack.toString([]);',
			'  }',
			'  static function stamp():Float {',
			'    return Sys.time();',
			'  }',
			'  static function sumRest(prefix:Int, rest:haxe.Rest<Int>):Int {',
			'    return prefix + rest.length;',
			'  }',
			'  static function useRest():Int {',
			'    return sumRest(1);',
			'  }',
			'  static function useExternRest():Dynamic {',
			'    return RestExtern.code("extern");',
			'  }',
			'  static function usePhpRest():Dynamic {',
			'    return php.Syntax.code("php extern");',
			'  }',
			'  static function check(c:Class<Dynamic>, n:String):Bool {',
			'    return Assert.contains(n, [], null) && Lambda.has(Type.getClassFields(c), n) && Lambda.array(Type.getClassFields(c)) != null && Type.getEnum(Type.typeof(n)) != null && Reflect.compare(n, n) == 0;',
			'  }',
			'  static function main() {',
			'    check(Main, "main");',
			'    render();',
			'    stamp();',
			'    useRest();',
			'    useExternRest();',
			'    usePhpRest();',
			'  }',
			'}',
		].join("\n");
		File.saveContent(mainHx, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, mainHx);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			EmitterStage.emitToDir(expanded, outDir, true, false);

			final mainMl = haxe.io.Path.join([outDir, 'Unit_Main.ml']);
			assertTrue(FileSystem.exists(mainMl), 'Expected Unit_Main.ml in emitted output.');
			final ocaml = File.getContent(mainMl);
			assertTrue(ocaml.indexOf('Haxe_CallStack.toString') >= 0 || ocaml.indexOf('CallStack.toString') >= 0,
				'Expected explicit short import to resolve to the imported `CallStack` provider.');
			assertTrue(ocaml.indexOf('Utest_Assert.contains') >= 0 || ocaml.indexOf('Assert.contains') >= 0,
				'Expected explicit imported short name `Assert` to resolve to the imported provider.');
			assertTrue(ocaml.indexOf('Lambda.has') >= 0, 'Expected root stdlib short name to remain `Lambda.has`.');
			assertTrue(ocaml.indexOf('Lambda.array') >= 0, 'Expected root stdlib short name to remain `Lambda.array`.');
			assertTrue(ocaml.indexOf('Type.getClassFields') >= 0, 'Expected root stdlib short name to remain `Type.getClassFields`.');
			assertTrue(ocaml.indexOf('Type.getEnum') >= 0, 'Expected root stdlib short name to remain `Type.getEnum`.');
			assertTrue(ocaml.indexOf('Reflect.compare') >= 0, 'Expected root stdlib short name to remain `Reflect.compare`.');
			assertTrue(ocaml.indexOf('HxSys.time') >= 0, 'Expected `Sys.time()` to lower to the HxSys runtime seam.');
			assertTrue(ocaml.indexOf('sumRest (1) (HxBootArray.create ())') >= 0,
				'Expected trailing `Rest<T>` parameter calls to lower to an explicit empty HxBootArray.');
			assertTrue(ocaml.indexOf('RestExtern.code ("extern") (HxBootArray.create ())') >= 0,
				'Expected extern trailing `Rest<T>` parameter calls to lower to an explicit empty HxBootArray.');
			assertTrue(ocaml.indexOf('Php_Syntax.code ("php extern") (HxBootArray.create ())') >= 0,
				'Expected packaged extern trailing `Rest<T>` parameter calls to lower to an explicit empty HxBootArray.');
			assertTrue(ocaml.indexOf('Unit_CallStack.') < 0, 'Found bad package-local qualification `Unit_CallStack`.');
			assertTrue(ocaml.indexOf('Unit_Assert.') < 0, 'Found bad package-local qualification `Unit_Assert`.');
			assertTrue(ocaml.indexOf('Unit_Lambda.') < 0, 'Found bad package-local qualification `Unit_Lambda`.');
			assertTrue(ocaml.indexOf('Unit_Type.') < 0, 'Found bad package-local qualification `Unit_Type`.');
			assertTrue(ocaml.indexOf('Unit_Reflect.') < 0, 'Found bad package-local qualification `Unit_Reflect`.');
			assertTrue(ocaml.indexOf('Haxe_Sys.') < 0, 'Found bad same-package qualification `Haxe_Sys`.');
			final typeShim = haxe.io.Path.join([outDir, 'Type.ml']);
			assertTrue(FileSystem.exists(typeShim), 'Expected Type.ml bootstrap import shim.');
			final typeShimOcaml = File.getContent(typeShim);
			assertTrue(typeShimOcaml.indexOf('include HxType') >= 0, 'Expected root Type shim to target HxType.');
			assertTrue(typeShimOcaml.indexOf('Haxe_macro_Type') < 0, 'Found bad root Type shim targeting haxe.macro.Type.');

			final haxeMainHx = haxe.io.Path.join([haxeSrcDir, 'haxe', 'Main.hx']);
			final haxeSrc = [
				'package haxe;',
				'class Main {',
				'  public static function stamp():Float {',
				'    return Sys.time();',
				'  }',
				'}',
			].join("\n");
			File.saveContent(haxeMainHx, haxeSrc);
			final haxeParsed = ParserStage.parse(haxeSrc, haxeMainHx);
			final haxeTyped = TyperStage.typeModule(haxeParsed);
			final haxeExpanded = MacroStage.expandProgram([haxeTyped], []);
			EmitterStage.emitToDir(haxeExpanded, haxeOutDir, true, false);

			final haxeMainMl = haxe.io.Path.join([haxeOutDir, 'Haxe_Main.ml']);
			assertTrue(FileSystem.exists(haxeMainMl), 'Expected Haxe_Main.ml in emitted output.');
			final haxeOcaml = File.getContent(haxeMainMl);
			assertTrue(haxeOcaml.indexOf('HxSys.time') >= 0, 'Expected same-package `Sys.time()` to lower to HxSys runtime seam.');
			assertTrue(haxeOcaml.indexOf('Haxe_Sys.') < 0, 'Found bad same-package `Haxe_Sys` qualification in package haxe output.');

			final phpSyntaxLocalHx = haxe.io.Path.join([phpSrcDir, 'php', 'Syntax.hx']);
			File.saveContent(phpSyntaxLocalHx, [
				'package php;',
				'extern class Syntax {',
				'  static function code(code:String, args:haxe.Rest<Dynamic>):Dynamic;',
				'}',
			].join("\n"));
			final phpBootHx = haxe.io.Path.join([phpSrcDir, 'php', 'Boot.hx']);
			final phpBootSrc = [
				'package php;',
				'class Boot {',
				'  public static function getPrefix():Dynamic {',
				'    return Syntax.code("self::PHP_PREFIX");',
				'  }',
				'}',
			].join("\n");
			File.saveContent(phpBootHx, phpBootSrc);
			final phpParsed = ParserStage.parse(phpBootSrc, phpBootHx);
			final phpTyped = TyperStage.typeModule(phpParsed);
			final phpExpanded = MacroStage.expandProgram([phpTyped], []);
			EmitterStage.emitToDir(phpExpanded, phpOutDir, true, false);

			final phpBootMl = haxe.io.Path.join([phpOutDir, 'Php_Boot.ml']);
			assertTrue(FileSystem.exists(phpBootMl), 'Expected Php_Boot.ml in emitted output.');
			final phpOcaml = File.getContent(phpBootMl);
			assertTrue(phpOcaml.indexOf('Php_Syntax.code ("self::PHP_PREFIX") (HxBootArray.create ())') >= 0,
				'Expected same-package short type `Syntax.code(...)` to lower with an explicit empty HxBootArray.');
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
