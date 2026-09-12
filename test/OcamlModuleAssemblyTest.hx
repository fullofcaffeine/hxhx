import reflaxe.ocaml.ast.OcamlModuleAssembly;
import reflaxe.ocaml.ast.OcamlModuleAssembly.assembleModules;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/** Checks alias identity, unchanged acyclic text, and refusal to duplicate private type uses. */
@:access(OcamlASTTraversalTest)
class OcamlModuleAssemblyTest {
	public static function run():Void {
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
		// A generated program module with a runtime-like name still owns its type.
		assembleModules([module("HxUser", "HxUser", TIdent("HxUser.t"))], printer);
	}

	static function module(name:String, dependency:String, result:OcamlTypeExpr):OcamlModuleAssemblyInput {
		return {
			name: name,
			parts: [
				ModuleDeclarations("(* header *)\n", [
					IType([{name: "t", params: [], kind: Alias(TIdent("Obj.t"))}], false),
					ILet([
						{
							name: "run",
							expr: EFun([PConst(CUnit)], EApp(EIdent(dependency + ".run"), [EConst(CUnit)])),
							signature: TArrow(TIdent("unit"), result)
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
