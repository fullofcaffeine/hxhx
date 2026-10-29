import haxe.macro.Context;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Check actual exported types and reject storage that cannot preserve nullable callbacks. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckNullableSignatures {
	public static function install():Void {
		Context.onAfterTyping(_ -> {
			final registry = new OcamlRepresentationRegistry();
			final context = new CompilationContext();
			final position = Context.currentPos();
			final callback = Context.resolveType(macro :Null<Int->Int>, position);
			final result = Context.resolveType(macro :Int, position);
			for (wrongStorage in [TIdent("int"), TArrow(TIdent("int"), TIdent("int"))])
				if (projectDeclarationSignature([callback], result, registry, _ -> wrongStorage, context) != null)
					throw "nullable callback accepted non-nullable storage";
			final unknown = Context.resolveType(macro :Null<Dynamic->Int>, position);
			if (projectDeclarationSignature([unknown], result, registry, _ -> TIdent("Obj.t"), context) != null)
				throw "nullable callback admitted an unknown argument carrier";
		});
		Context.onAfterGenerate(() -> {
			check("create", "Obj.t -> t");
			check("apply", "t -> int -> Obj.t -> int");
			check("factory", "bool -> Obj.t");
		});
	}

	/** Read retained syntax from lowering so generated text cannot hide a missing signature. */
	static function check(name:String, expected:String):Void {
		final items = OcamlCompiler.instance.moduleChunks.itemsFor("Left", "Left");
		if (items == null)
			throw "missing Left module syntax";
		for (item in items)
			switch (item) {
				case ILet(bindings, _):
					for (binding in bindings)
						if (binding.name == name) {
							if (binding.signature == null || new OcamlASTPrinter().printType(binding.signature) != expected)
								throw "wrong nullable declaration signature: " + name;
							return;
						}
				case IType(_, _):
			}
		throw "missing nullable declaration: " + name;
	}
}
