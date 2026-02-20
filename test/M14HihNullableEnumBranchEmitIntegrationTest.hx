import sys.FileSystem;
import sys.io.File;

class M14HihNullableEnumBranchEmitIntegrationTest {
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

	static function findMainMl(outDir:String):String {
		for (entry in FileSystem.readDirectory(outDir)) {
			if (entry == "Main.ml" || entry == "main.ml" || StringTools.endsWith(entry, "__Main.ml"))
				return haxe.io.Path.join([outDir, entry]);
		}
		throw "Stage3 output missing main module (`Main.ml` or `*__Main.ml`).";
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize(".tmp/m14_hih_nullable_enum_branch_emit_" + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, "src"]);
		final outDir = haxe.io.Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final mainHx = haxe.io.Path.join([srcDir, "Main.hx"]);
		final src = [
			"enum HxStmt {",
			"  SNop;",
			"  SIf(cond:Int, thenBranch:HxStmt, elseBranch:Null<HxStmt>);",
			"}",
			"class Main {",
			"  static function acceptKeyword():Bool return true;",
			"  static function parseStmt(stop:Void->Bool):HxStmt return SNop;",
			"  static function main() {",
			"    final stop = () -> false;",
			"    final thenBranch = parseStmt(stop);",
			"    final elseBranch = acceptKeyword() ? parseStmt(stop) : null;",
			"    final stmt = SIf(1, thenBranch, elseBranch);",
			"    Sys.println(Std.string(stmt != null));",
			"  }",
			"}",
		].join("\n");
		File.saveContent(mainHx, src);

		final parsed = ParserStage.parse(src, mainHx);
		final typed = TyperStage.typeModule(parsed);
		final expanded = MacroStage.expandProgram([typed], []);
		final exePath = EmitterStage.emitToDir(expanded, outDir, true);
		assertTrue(FileSystem.exists(exePath), "Emitter did not produce executable: " + exePath);

		final mainMl = findMainMl(outDir);
		final ocaml = File.getContent(mainMl);
		assertTrue(ocaml.indexOf('Obj.obj (HxEnum.unbox_or_obj "HxStmt"') < 0,
			'Nullable enum branch regression: found `Obj.obj (HxEnum.unbox_or_obj "HxStmt"` in emitted OCaml.');

		deleteRecursive(tmpRoot);
	}
}
