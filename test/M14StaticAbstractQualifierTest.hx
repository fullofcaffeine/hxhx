import sys.FileSystem;
import sys.io.File;

/** Static abstract owners name declarations; their module prefixes are not evaluated class objects. */
class M14StaticAbstractQualifierTest {
	static function remove(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (name in FileSystem.readDirectory(path))
				remove(path + "/" + name);
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}

	static function main():Void {
		final root = ".tmp/static-abstract-qualifier-" + Date.now().getTime();
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = 'import Main.Code as Alias;
abstract Code(Int) {
 public static inline function fromInt(value:Int):Code { return cast value; }
}
class Main {
 static function direct():Code { return Main.Code.fromInt(1); }
 static function alias():Code { return Alias.fromInt(2); }
 static function callback():Code { var build = Main.Code.fromInt; return build(3); }
 static function shadow(Main:{Code:{fromInt:Int->Int}}):Int { return Main.Code.fromInt(4); }
 static function receiver():{Code:{fromInt:Int->Int}} {
  Sys.println("receiver");
  return {Code:{fromInt:function(value:Int):Int { return value + 10; }}};
 }
 static function fieldValue():Int { return receiver().Code.fromInt(5); }
 static function main():Void {
  Sys.println(Std.string(cast direct()));
  Sys.println(Std.string(cast alias()));
  Sys.println(Std.string(cast callback()));
  Sys.println(shadow(receiver()));
  Sys.println(fieldValue());
 }
}';
		File.saveContent(path, source);
		final expected = "1\n2\n3\nreceiver\n14\nreceiver\n15\n";
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final module = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		for (owner in module.getBackendProjection().getClasses())
			for (fn in owner.getFunctions())
				if (["direct", "alias", "callback", "shadow", "fieldValue"].indexOf(HxFunctionDecl.getName(fn.getDeclaration())) >= 0
					&& fn.getRuntimeTypeCatalog().getEntries().length != 0)
					throw "static abstract qualification introduced a runtime class object in " + HxFunctionDecl.getName(fn.getDeclaration());
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([module], []), root + "/native");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		remove(root);
		Sys.println("STATIC_ABSTRACT_QUALIFIER:PASS");
	}
}
