import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Checks callback exports without granting representations to unknown nested types. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckCallbackSignatures {
	public static function install():Void {
		Context.onAfterTyping(_ -> {
			for (syntax in [macro :Dynamic->String, macro :Int->Dynamic, macro :(?value:Int) -> String]) {
				final type = Context.resolveType(syntax, Context.currentPos());
				final signature = projectDeclarationSignature([type], Context.getType("String"), new OcamlRepresentationRegistry(),
					_ -> throw "unsupported callback reached the nominal mapper", new CompilationContext());
				if (signature != null)
					throw "unsupported callback gained a declaration signature";
			}
		});
		Context.onAfterGenerate(() -> {
			for (moduleId in ["First", "Second"]) {
				final items = OcamlCompiler.instance.moduleChunks.itemsFor(moduleId, moduleId);
				if (items == null)
					throw "missing retained module: " + moduleId;
				final expected:Map<String, String> = [
					"run" => "(int -> string) -> int -> string",
					"empty" => "(unit -> string) -> string",
					"retain" => "(int -> string) -> int -> string",
					"pair" => "(int -> string -> string) -> string",
					"optional" => "(string -> string) -> string"
				];
				for (item in items)
					switch (item) {
						case ILet(bindings, _):
							for (binding in bindings)
								if (expected.exists(binding.name)) {
									if (binding.signature == null
										|| new OcamlASTPrinter().printType(binding.signature) != expected.get(binding.name))
										throw "callback declaration lost its function type: " + moduleId + "." + binding.name;
									expected.remove(binding.name);
								}
						case IType(_, _):
					}
				if (expected.keys().hasNext())
					throw "missing callback export: " + moduleId;
			}
		});
	}
}
