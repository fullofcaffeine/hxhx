import reflaxe.ocaml.ast.OcamlModuleAssembly;
import reflaxe.ocaml.ast.OcamlModuleAssembly.assembleModules;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/** Checks alias identity, unchanged acyclic text, and refusal to duplicate private type uses. */
@:access(OcamlASTTraversalTest)
class OcamlModuleAssemblyTest {
	public static function run():Void {
		OcamlModuleValuesTest.run();
		checkBatchDiagnostics();
		final printer = new OcamlASTPrinter();
		final left = module("Left", "Right", TIdent("int"));
		final right = module("Right", "Left", TIdent("int"));
		final output = assembleModules([right, left], printer);
		if (output.get("Right") != "include Left.Right")
			throw "recursive module alias changed its public owner";
		final canonical = output.get("Left");
		if (canonical == null
			|| !StringTools.startsWith(canonical, "module rec Left : sig\n")
			|| !StringTools.endsWith(canonical, "\n\ninclude Left"))
			throw "canonical file failed to retain its original public values";
		if (assembleModules([left, right], printer).get("Left") != canonical)
			throw "input order changed recursive output";
		final opaque:OcamlModuleAssemblyInput = {name: "External", parts: [OpaqueModuleText("opaque text")]};
		if (assembleModules([opaque], printer).get("External") != "opaque text")
			throw "acyclic framework text changed";
		final plain = module("Plain", "External", TIdent("int"));
		final expected = switch (plain.parts[0]) {
			case ModuleDeclarations(header, items): header + printer.printModule(items);
			case _: throw "test declaration lost its structure";
		};
		if (assembleModules([plain, opaque], printer).get("Plain") != expected)
			throw "acyclic declaration text changed";
		reject([left, right, opaque], "opaque-output");
		reject([module("Private", "Private", OcamlASTTraversalTest.allTypeConstructors())], "signature-runtime-copy-required");
		reject([module("HxArray", "HxArray", OcamlASTTraversalTest.allTypeConstructors())], "signature-runtime-copy-required");
		reject([module("Private", "Private", TIdent("HxArray.t"))], "signature-runtime-copy-required");
		var plainRejected = false;
		try {
			assembleModules([module("Private", "Private", TApp("option", [TIdent("HxArray.t")]))], printer, (type, _) -> type);
		} catch (message:String) {
			plainRejected = message.indexOf("signature-runtime-copy-required") >= 0;
		}
		if (!plainRejected)
			throw "An output callback must not authorize a plain private type.";
		// A generated program module with a runtime-like name still owns its type.
		assembleModules([module("HxUser", "HxUser", TIdent("HxUser.t"))], printer);
		final literalLeft = withLiteral(module("Left", "Right", TIdent("int")));
		final literalOutput = assembleModules([literalLeft, right], printer).get("Left");
		if (literalOutput == null || literalOutput.indexOf("val tag : string") < 0 || literalOutput.indexOf("let tag = \"ready\"") < 0)
			throw "literal export or initialization changed";
		reject([literalLeft, withLiteral(module("Right", "Left", TIdent("int")))], "unsafe-literal-cycle");
		reject([withLiteral(module("Self", "Self", TIdent("int")))], "unsafe-literal-cycle");
		// A safe member elsewhere in the group cannot repair an unsafe subcycle.
		final unsafeRight = withLiteral(module("Right", "Left", TIdent("int")));
		unsafeRight.parts.push(ModuleDeclarations("", [
			ILet([
				{
					name: "viaSafe",
					expr: EFun([PConst(CUnit)], EApp(EIdent("Safe.run"), [EConst(CUnit)])),
					signature: TArrow(TIdent("unit"), TIdent("int"))
				}
			], false)
		]));
		reject([literalLeft, unsafeRight, module("Safe", "Left", TIdent("int"))], "unsafe-literal-cycle");
		// Multiple literal-bearing members are valid when every cycle crosses Safe.
		assembleModules([
			withLiteral(module("Left", "Right", TIdent("int"))),
			withLiteral(module("Right", "Safe", TIdent("int"))),
			module("Safe", "Left", TIdent("int"))
		], printer);
		assembleModules([typeOnly("Left", "Right"), typeOnly("Right", "Left")], printer);
	}

	static function typeOnly(name:String, dependency:String):OcamlModuleAssemblyInput {
		return withLiteral({
			name: name,
			parts: [
				ModuleDeclarations("", [
					IType([
						{
							name: "t",
							params: [],
							kind: Record([
								{name: "other", typ: TApp("option", [TIdent(dependency + ".t")]), isMutable: false}
							])
						}
					], false)
				])
			]
		});
	}

	static function withLiteral(value:OcamlModuleAssemblyInput):OcamlModuleAssemblyInput {
		value.parts.push(ModuleDeclarations("", [ILet([{name: "tag", expr: EConst(CString("ready"))}], false)]));
		return value;
	}

	/** Reports every invalid module before spending any runtime references on output. */
	static function checkBatchDiagnostics():Void {
		final input = [
			module("AReady", "BMissing", TIdent("int")),
			module("BMissing", "CMissing", null),
			module("CMissing", "AReady", null),
			module("DMissing", "EMissing", null),
			module("EMissing", "DMissing", null)
		];
		function diagnostic(modules:Array<OcamlModuleAssemblyInput>):String {
			var copies = 0;
			var failure = "";
			try {
				assembleModules(modules, new OcamlASTPrinter(), (type, _) -> {
					copies++;
					return type;
				});
			} catch (message:String) {
				failure = message;
			}
			for (name in ["BMissing", "CMissing", "DMissing", "EMissing"])
				if (failure.indexOf(name + ": MissingSignature(run)") < 0)
					throw "module rejection omitted " + name + ": " + failure;
			if (copies != 0)
				throw "rejected declarations activated signature output uses";
			return failure;
		}
		final expected = diagnostic(input);
		input.reverse();
		if (diagnostic(input) != expected)
			throw "input order changed the module diagnostics";
		var unsafeCopies = 0;
		var unsafeRejected = false;
		try {
			assembleModules([
				withLiteral(module("Left", "Right", TIdent("int"))),
				withLiteral(module("Right", "Left", TIdent("int")))
			], new OcamlASTPrinter(), (type, _) -> {
				unsafeCopies++;
				return type;
			});
		} catch (message:String) {
			unsafeRejected = message.indexOf("unsafe-literal-cycle") >= 0;
		}
		if (!unsafeRejected || unsafeCopies != 0)
			throw "unsafe initialization activated signature output uses";
	}

	static function module(name:String, dependency:String, result:Null<OcamlTypeExpr>):OcamlModuleAssemblyInput {
		return {
			name: name,
			parts: [
				ModuleDeclarations("(* header *)\n", [
					IType([{name: "t", params: [], kind: Alias(TIdent("Obj.t"))}], false),
					ILet([
						{
							name: "run",
							expr: EFun([PConst(CUnit)], EApp(EIdent(dependency + ".run"), [EConst(CUnit)])),
							signature: result == null ? null : TArrow(TIdent("unit"), result)
						}
					], false)
				])
			]
		};
	}

	static function reject(input:Array<OcamlModuleAssemblyInput>, code:String):Void {
		var rejected = false;
		try {
			assembleModules(input, new OcamlASTPrinter());
		} catch (message:String) {
			rejected = message.indexOf("ocaml-module-cycle:" + code) >= 0;
		}
		if (!rejected)
			throw "module assembly did not reject " + code;
	}
}
