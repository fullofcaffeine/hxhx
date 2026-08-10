import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlRawInjection;
import reflaxe.ocaml.ast.OcamlRawInjection.OcamlRawInjectionMaterializationResult;
import reflaxe.ocaml.ast.OcamlRawInjection.OcamlRawInjectionPlanResult;
import reflaxe.ocaml.ast.OcamlRawInterpolationPlan.OcamlRawInterpolationPlanPart;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.ast.OcamlTypeExpr;

class OcamlASTPrinterTest {
	static function assertEq(expected:String, actual:String, label:String):Void {
		if (expected != actual) {
			throw label + "\n--- expected ---\n" + expected + "\n--- actual ---\n" + actual;
		}
	}

	/** Proves that a raw template cannot discard or duplicate one typed expression. */
	static function verifyRawInterpolationPlan():Void {
		switch (OcamlRawInjection.plan("before {0} middle {1} after", 2)) {
			case PlanReady(plan):
				switch (plan.parts()) {
					case [
						AuthoredText("before "),
						TypedArgument(0),
						AuthoredText(" middle "),
						TypedArgument(1),
						AuthoredText(" after")
					]:
					case other:
						throw "valid raw interpolation plan changed: " + Std.string(other);
				}
			case PlanInvalid(message):
				throw "valid raw interpolation plan failed: " + message;
		}

		for (testCase in [
			{
				label: "duplicate",
				template: "{0} + {0}",
				arguments: 1,
				expected: "exactly once; found 2"
			},
			{
				label: "discarded",
				template: "constant",
				arguments: 1,
				expected: "exactly once; found 0"
			},
			{
				label: "out of range",
				template: "{1}",
				arguments: 1,
				expected: "no matching typed argument"
			},
			{
				label: "joined before",
				template: "H{0}",
				arguments: 1,
				expected: "separated from authored identifier text"
			},
			{
				label: "joined after",
				template: "{0}xRuntime",
				arguments: 1,
				expected: "separated from authored identifier text"
			},
			{
				label: "private runtime",
				template: "HxRuntime.hx_null",
				arguments: 0,
				expected: "cannot name compiler-private runtime identifier HxRuntime"
			}
		]) {
			switch (OcamlRawInjection.plan(testCase.template, testCase.arguments)) {
				case PlanInvalid(message) if (message.indexOf(testCase.expected) >= 0):
				case PlanInvalid(message):
					throw testCase.label + " raw interpolation error changed: " + message;
				case PlanReady(_):
					throw testCase.label + " raw interpolation unexpectedly succeeded";
			}
		}

		switch (OcamlRawInjection.plan("{0}", 1)) {
			case PlanInvalid(message):
				throw "valid raw materialization plan failed: " + message;
			case PlanReady(plan):
				switch (OcamlRawInjection.materialize(plan, [])) {
					case InjectionInvalid(message) if (message.indexOf("expected 1 typed arguments but received 0") >= 0):
					case InjectionInvalid(message):
						throw "raw materialization cardinality error changed: " + message;
					case InjectionReady(_):
						throw "raw materialization accepted a missing typed argument";
				}
		}
	}

	/**
		Proves that valid generated syntax can be much deeper than the Haxe
		process call stack. Large source-building functions produce this shape
		when their local computations become nested OCaml `let ... in` nodes.
	**/
	static function verifyDeepExpressionPrintingIsStackSafe(printer:OcamlASTPrinter):Void {
		final nestingDepth = 20000;
		var expression:OcamlExpr = OcamlExpr.EIdent("leaf");
		for (_ in 0...nestingDepth)
			expression = OcamlExpr.ELet("value", OcamlExpr.EConst(OcamlConst.CUnit), expression, false);

		final rendered = printer.printExpr(expression);
		final layer = "let value = () in ";
		assertEq(Std.string((layer.length * nestingDepth) + "leaf".length), Std.string(rendered.length), "deep expression output length");
		assertEq("leaf", rendered.substr(rendered.length - "leaf".length), "deep expression leaf");
	}

	static function main() {
		OcamlASTTraversalTest.run();
		final p = new OcamlASTPrinter();
		verifyDeepExpressionPrintingIsStackSafe(p);
		verifyRawInterpolationPlan();

		// const + escaping
		assertEq("\"a\\n\\t\\\\\\\"b\"", p.printExpr(OcamlExpr.EConst(OcamlConst.CString("a\n\t\\\"b"))), "string escape");

		// let-in
		assertEq("let x = 1 in x", p.printExpr(OcamlExpr.ELet("x", OcamlExpr.EConst(OcamlConst.CInt(1)), OcamlExpr.EIdent("x"), false)), "let-in");
		assertEq("HxArray.set", p.printExpr(OcamlASTTraversalTest.runtimeIdentifierExpression()),
			"checked runtime identifier prints the exact planned symbol without printer decisions");
		assertEq("HxArray.ObjStore runtime_pattern_arg", p.printPat(OcamlASTTraversalTest.runtimeConstructorPattern()),
			"checked runtime pattern prints the exact planned constructor without printer decisions");
		final rawExpression = OcamlASTTraversalTest.rawInjectionExpression("(ignore {0})", [OcamlExpr.EIdent("visible_child")]);
		assertEq("(ignore visible_child)", p.printExpr(rawExpression), "raw interpolation prints authored text around a structured expression child");
		switch (rawExpression) {
			case ERawInjection(injection):
				final callerCopy = injection.segments();
				callerCopy.resize(0);
				assertEq("(ignore visible_child)", p.printExpr(rawExpression), "mutating a returned segment list cannot change validated raw syntax");
			case _:
				throw "raw fixture did not produce the checked raw AST node";
		}

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
