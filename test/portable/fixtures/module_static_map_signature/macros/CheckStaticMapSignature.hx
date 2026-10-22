import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectStaticMapDeclarationSignature;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Check the retained map declaration and the boundary around generic scalar values. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckStaticMapSignature {
	public static function install():Void {
		Context.onAfterTyping(_ -> {
			final owner = switch (Context.getType("Left")) {
				case TInst(reference, _): reference.get();
				case _: throw "missing Left";
			};
			final method = owner.statics.get().filter(field -> field.name == "count")[0];
			final owned = method.params.map(parameter -> parameter.t);
			final integer = Context.resolveType(macro :Int, Context.currentPos());
			final registry = new OcamlRepresentationRegistry();
			final context = new CompilationContext();
			if (projectStaticMapDeclarationSignature([owned[0]], integer, registry, _ -> TIdent("Obj.t"), context, owned) != null)
				throw "bare generic argument acquired map-storage permission";
			if (projectStaticMapDeclarationSignature([integer], owned[0], registry, _ -> TIdent("Obj.t"), context, owned) != null)
				throw "generic result acquired map-storage permission";
		});
		Context.onAfterGenerate(() -> {
			final items = OcamlCompiler.instance.moduleChunks.itemsFor("Left", "Left");
			if (items == null)
				throw "missing Left module";
			for (item in items)
				switch (item) {
					case ILet(bindings, _):
						for (binding in bindings)
							if (binding.name == "count") {
								switch (binding.signature) {
									case TArrow(TRuntimeApp(_, [TIdent("Obj.t")]), TIdent("int")): return;
									case _: throw "count lost its existing map carrier or concrete result";
								}
							}
					case IType(_, _):
				}
			throw "missing count declaration";
		});
	}
}
