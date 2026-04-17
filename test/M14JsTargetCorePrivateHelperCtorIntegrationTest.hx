import backend.BackendContext;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14JsTargetCorePrivateHelperCtorIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + " (missing `" + needle + "`)";
	}

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

	static function hasClass(classes:Array<HxClassDecl>, name:String):Bool {
		for (cls in classes)
			if (HxClassDecl.getName(cls) == name)
				return true;
		return false;
	}

	static function runNodeScript(jsPath:String):String {
		final process = new sys.io.Process("node", [jsPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		assertTrue(exitCode == 0, "node execution failed for " + jsPath + " with exit " + exitCode + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function main():Void {
		final tmpRoot = Path.normalize(".tmp/m14_js_target_core_private_helper_ctor_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		var failure:Null<String> = null;
		try {
			final helperSource = [
				"class Main {",
				"  static var selfModifyingVar:()->Int = function() {",
				"    return 1;",
				"  }",
				"}",
				"private class Parent {",
				"  public function new() {}",
				"  public function rec(n:Int):Int { return n; }",
				"}",
				"private class Child extends Parent {",
				"  override public function rec(n:Int):Int { return super.rec(n); }",
				"}"
			].join("\n");
			final helpers = ParserStageScanHelpers.scanModuleLocalHelperClasses(helperSource, "Main");
			assertTrue(hasClass(helpers, "Parent"), "private helper scanner should not skip Parent after a function-valued static field");
			assertTrue(hasClass(helpers, "Child"), "private helper scanner should keep later Child helper class");

			final parentVar = HxStmt.SVar("parent", "", HxExpr.ENew("Parent", []), HxPos.unknown());
			final childVar = HxStmt.SVar("child", "", HxExpr.ENew("Child", []), HxPos.unknown());
			final printParent = HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("Sys"), "println"), [
				HxExpr.EBinop("+", HxExpr.EString("parent="), HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("parent"), "rec"), [HxExpr.EInt(2)]))
			]), HxPos.unknown());
			final printChild = HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("Sys"), "println"), [
				HxExpr.EBinop("+", HxExpr.EString("child="), HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("child"), "rec"), [HxExpr.EInt(3)]))
			]), HxPos.unknown());
			final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [parentVar, childVar, printParent, printChild], "");
			final mainClass = new HxClassDecl("Main", true, [mainFn], []);
			final classes = [mainClass].concat(helpers);
			final decl = new HxModuleDecl("", [], mainClass, classes, false, false);
			final parsed = new ParsedModule(helperSource, decl, "Main.hx");
			final program = MacroStage.expandProgram([TyperStage.typeModule(parsed)], []);

			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			new JsBackend().emit(program, new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			final js = File.getContent(artifactPath);
			assertContains(js, "var parent = new __hx_cls_Parent();", "Parent constructor should resolve through scanned helper class refs");
			assertContains(js, "var child = new __hx_cls_Child();", "Child constructor should resolve through scanned helper class refs");

			final stdout = runNodeScript(artifactPath);
			assertContains(stdout, "parent=2", "Parent helper method should execute");
			assertContains(stdout, "child=3", "Child override should execute through scanned helper method");
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}

		if (failure != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw failure;
		}
		deleteRecursive(tmpRoot);
	}
}
