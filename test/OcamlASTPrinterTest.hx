import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.ast.OcamlTypeExpr;

class OcamlASTPrinterTest {
	static function assertEq(expected:String, actual:String, label:String):Void {
		if (expected != actual) {
			throw label + "\n--- expected ---\n" + expected + "\n--- actual ---\n" + actual;
		}
	}

	static function main() {
		final p = new OcamlASTPrinter();

		// const + escaping
		assertEq("\"a\\n\\t\\\\\\\"b\"", p.printExpr(OcamlExpr.EConst(OcamlConst.CString("a\n\t\\\"b"))), "string escape");

		// let-in
		assertEq("let x = 1 in x", p.printExpr(OcamlExpr.ELet("x", OcamlExpr.EConst(OcamlConst.CInt(1)), OcamlExpr.EIdent("x"), false)), "let-in");

		// application + arg parens for low-precedence expressions
		assertEq("f (let x = 1 in x)", p.printExpr(OcamlExpr.EApp(OcamlExpr.EIdent("f"), [
			OcamlExpr.ELet("x", OcamlExpr.EConst(OcamlConst.CInt(1)), OcamlExpr.EIdent("x"), false)
		])), "app arg parens");

		// match formatting
		assertEq("match x with\n  | _ -> 1", p.printExpr(OcamlExpr.EMatch(OcamlExpr.EIdent("x"), [
			{
				pat: OcamlPat.PAny,
				guard: null,
				expr: OcamlExpr.EConst(OcamlConst.CInt(1))
			}
		])), "match");

		// sequence formatting
		assertEq("(\n  a;\n  b\n)", p.printExpr(OcamlExpr.ESeq([OcamlExpr.EIdent("a"), OcamlExpr.EIdent("b")])), "seq");

		// type decls
		assertEq("type t = { mutable x : int; y : string }", p.printItem(OcamlModuleItem.IType([
			{
				name: "t",
				params: [],
				kind: OcamlTypeDeclKind.Record([
					{name: "x", isMutable: true, typ: OcamlTypeExpr.TIdent("int")},
					{name: "y", isMutable: false, typ: OcamlTypeExpr.TIdent("string")}
				])
			}
		], false)), "type record");

		assertEq("type t =\n| A\n| B of int * string", p.printItem(OcamlModuleItem.IType([
			{
				name: "t",
				params: [],
				kind: OcamlTypeDeclKind.Variant([
					{name: "A", args: []},
					{name: "B", args: [OcamlTypeExpr.TIdent("int"), OcamlTypeExpr.TIdent("string")]}
				])
			}
		], false)), "type variant");

		// Optional compile-check if `ocamlc` is available on PATH.
		// This is best-effort and should not fail the suite on machines without OCaml installed.
		try {
			final ocamlc = findOnPath("ocamlc");
			if (ocamlc != null) {
				final tmpDir = ".tmp_ocaml_printer_check";
				sys.FileSystem.createDirectory(tmpDir);
				final path = tmpDir + "/PrinterCheck.ml";
				sys.io.File.saveContent(path, p.printModule([
					OcamlModuleItem.IType([
						{
							name: "t",
							params: [],
							kind: OcamlTypeDeclKind.Record([{name: "x", isMutable: true, typ: OcamlTypeExpr.TIdent("int")}])
						}
					], false),
					OcamlModuleItem.ILet([{name: "x", expr: OcamlExpr.EConst(OcamlConst.CInt(1))}], false)
				]) + "\n");
				final exitCode = Sys.command(ocamlc, ["-c", path]);
				if (exitCode != 0)
					throw "ocamlc compile-check failed with exit code " + exitCode;
				try
					sys.FileSystem.deleteFile(path)
				catch (_:Dynamic) {}
				try
					sys.FileSystem.deleteFile(tmpDir + "/PrinterCheck.cmi")
				catch (_:Dynamic) {}
				try
					sys.FileSystem.deleteFile(tmpDir + "/PrinterCheck.cmo")
				catch (_:Dynamic) {}
				try
					sys.FileSystem.deleteDirectory(tmpDir)
				catch (_:Dynamic) {}
			}
		} catch (_:Dynamic) {}
	}

	static function findOnPath(exe:String):Null<String> {
		final path = Sys.getEnv("PATH");
		if (path == null || path.length == 0)
			return null;
		for (dir in path.split(":")) {
			if (dir == null || dir.length == 0)
				continue;
			final candidate = dir + "/" + exe;
			try {
				if (sys.FileSystem.exists(candidate))
					return candidate;
			} catch (_:Dynamic) {}
		}
		return null;
	}
}
