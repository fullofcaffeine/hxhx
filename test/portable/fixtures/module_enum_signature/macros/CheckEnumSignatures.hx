import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Checks declaration ownership independently of the optional enum-result optimization. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckEnumSignatures {
	public static function install():Void {
		Context.onAfterTyping(_ -> {
			final registry = new OcamlRepresentationRegistry();
			final context = new CompilationContext();
			final generic = Context.resolveType(macro :GenericToken<String>, Context.currentPos());
			for (type in [
				generic,
				Context.getType("ForeignToken"),
				Context.resolveType(macro :Null<GenericToken<String>>, Context.currentPos()),
				Context.resolveType(macro :Null<ForeignToken>, Context.currentPos())
			]) {
				if (projectDeclarationSignature([type], Context.getType("Void"), registry, unexpectedNominal, context) != null)
					throw "generic or extern enum gained an unproved declaration signature";
			}
			final nullable = Context.resolveType(macro :Null<Token>, Context.currentPos());
			if (projectDeclarationSignature([nullable], Context.getType("Void"), registry, _ -> TIdent("Token.token"), context) != null)
				throw "a nullable enum incorrectly reused the unboxed variant carrier";
		});
		Context.onAfterGenerate(() -> {
			final compiler = OcamlCompiler.instance;
			if (compiler.representationRegistry.nativeEnumValue("Token") != null)
				throw "the fixture must not rely on an optimized enum-result proof";
			for (moduleId in ["First", "Second"]) {
				final items = compiler.moduleChunks.itemsFor(moduleId, moduleId);
				if (items == null)
					throw "missing retained module: " + moduleId;
				final expected:Map<String, String> = ["accept" => "Token.token -> string", "nullable" => "Obj.t -> Obj.t"];
				if (moduleId == "First") {
					expected.set("maybe", "Obj.t -> string");
					expected.set("optional", "Obj.t -> string");
				}
				for (item in items)
					switch (item) {
						case ILet(bindings, _):
							for (binding in bindings)
								if (expected.exists(binding.name)) {
									if (binding.signature == null
										|| new OcamlASTPrinter().printType(binding.signature) != expected.get(binding.name))
										throw "enum parameter lost its declared variant type: " + moduleId;
									expected.remove(binding.name);
								}
						case IType(_, _):
					}
				if (expected.keys().hasNext())
					throw "missing enum consumer: " + moduleId;
			}
		});
	}

	static function unexpectedNominal(type:Type):OcamlTypeExpr {
		throw "unsupported enum reached the nominal type mapper";
	}
}
