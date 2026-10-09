import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.target.OcamlTargetConstructionLowerer.buildAllocation;
import sys.io.File;

/** Execute the shared allocation wrapper against an independently authored OCaml observer. */
class ConstructionFixture {
	static function main():Void {
		final expression = buildAllocation({
			parameters: [PVar("value"), PVar("fail")],
			initializer: EApp(EIdent("Observer.allocate"), [EIdent("value")]),
			body: EApp(EIdent("Observer.initialize"), [EIdent("self"), EIdent("value"), EIdent("fail")])
		});
		final directory = ".tmp/shared-construction-" + Date.now().getTime() + "-" + Std.random(0x3fffffff);
		sys.FileSystem.createDirectory(directory);
		File.copy("test/reflaxe_ocaml_shared_construction/Observer.ml", directory + "/Observer.ml");
		File.saveContent(directory
			+ "/Main.ml", "let create = "
			+ new OcamlASTPrinter().printExpr(expression)
			+ "\nlet () = Observer.verify create\n");
		final original = Sys.getCwd();
		try {
			Sys.setCwd(directory);
			if (Sys.command("ocamlopt", ["Observer.ml", "Main.ml", "-o", "observer.exe"]) != 0 || Sys.command("./observer.exe", []) != 0)
				throw "shared constructor allocation observer failed";
			Sys.setCwd(original);
		} catch (error:haxe.Exception) {
			Sys.setCwd(original);
			throw error;
		}
		Sys.println("REFLAXE_OCAML_SHARED_CONSTRUCTION:PASS");
	}
}
