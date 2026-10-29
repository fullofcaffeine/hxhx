import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.produce;
import reflaxe.ocaml.ast.OcamlGenericCallEmitter.convertView;
import reflaxe.ocaml.lowered.OcamlCallableOriginKind;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;

/** Ordinary compiler hosts must execute the shared callback syntax, including its preserved identity. */
class OrdinaryCallableViewSyntaxTest {
	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "Callback syntax command failed: " + command + "\n" + output + errors;
		return output;
	}

	static function main():Void {
		var next = 0;
		function fresh(role:String):String
			return "__hx_" + role + "_" + next++;
		final printer = new OcamlASTPrinter();
		final origin = produce(StaticDeclaration("syntax-probe:consume"), EIdent("consume"), fresh);
		final view = convertView(AdaptFunction([BoxValue], Identity), EIdent("source"), "syntax-probe:view", fresh,
			(_, _) -> throw "An integer boxing adapter must not request private runtime helpers");
		final root = ".tmp/ordinary_callable_view_syntax";
		sys.FileSystem.createDirectory(root);
		// The native observer is independent of the syntax tree: invoking the view must return 7 and retain the source identity.
		final source = "let consume (value : Obj.t) : Obj.t = value\nlet source = "
			+ printer.printExpr(origin)
			+ "\nlet view = "
			+ printer.printExpr(view)
			+ "\nlet () = Printf.printf \"%d\\n%b\\n\" (Obj.obj ((Stdlib.fst view) 7) : int) ((Stdlib.snd source) == (Stdlib.snd view))\n";
		sys.io.File.saveContent(root + "/Main.ml", source);
		run("ocamlopt", ["-o", root + "/main.exe", root + "/Main.ml"]);
		if (run(root + "/main.exe", []) != "7\ntrue\n")
			throw "Shared callback syntax changed invocation or source identity";
		Sys.println("ORDINARY_CALLABLE_VIEW_SYNTAX:PASS");
	}
}
