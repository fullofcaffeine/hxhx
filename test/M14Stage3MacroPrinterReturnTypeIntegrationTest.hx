import sys.FileSystem;
import sys.io.File;

class M14Stage3MacroPrinterReturnTypeIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_macro_printer_return_type_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final printerDir = haxe.io.Path.join([srcDir, 'haxe', 'macro']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(printerDir);

		final printerHx = haxe.io.Path.join([printerDir, 'Printer.hx']);
		final src = [
			'package haxe.macro;',
			'class Printer {',
			'  public function new() {}',
			'  public function printComplexType(ct:Dynamic) {',
			'    switch (ct) {',
			'      case _: "";',
			'    }',
			'  }',
			'  public function printBinop(op:Dynamic) {',
			'    switch (op) {',
			'      case _: "";',
			'    }',
			'  }',
			'  public function printTypeParamDecl(tpd:Dynamic) {',
			'    return "=" + printComplexType(tpd.defaultType) + printBinop(tpd.binop);',
			'  }',
			'}',
		].join("\n");
		File.saveContent(printerHx, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, printerHx);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			EmitterStage.emitToDir(expanded, outDir, false, false);

			final printerMl = haxe.io.Path.join([outDir, 'Haxe_macro_Printer.ml']);
			assertTrue(FileSystem.exists(printerMl), 'Expected Haxe_macro_Printer.ml in emitted output.');
			final ocaml = File.getContent(printerMl);
			assertTrue(ocaml.indexOf('printComplexType (this_ : _) (ct : _) : string') >= 0,
				'Stage3 macro Printer return override did not type printComplexType as string.');
			assertTrue(ocaml.indexOf('printBinop (this_ : _) (op : _) : string') >= 0,
				'Stage3 macro Printer return override did not type printBinop as string.');
			assertTrue(ocaml.indexOf('printComplexType (this_ : _) (ct : _) : unit') < 0,
				'Stage3 macro Printer regression: printComplexType was emitted as unit.');
			assertTrue(ocaml.indexOf('printBinop (this_ : _) (op : _) : unit') < 0,
				'Stage3 macro Printer regression: printBinop was emitted as unit.');
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
