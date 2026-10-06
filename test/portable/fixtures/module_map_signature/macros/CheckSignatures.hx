import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Checks exact map exports and keeps unsupported element types outside that contract. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckSignatures {
	public static function install():Void {
		Context.onAfterTyping(_ -> {
			final representations = new OcamlRepresentationRegistry();
			final context = new CompilationContext();
			final voidType = Context.getType("Void");
			for (source in [
				"haxe.ds.StringMap<Dynamic>",
				"haxe.ds.IntMap<Array<Dynamic>>",
				"haxe.ds.ObjectMap<Key, Dynamic>",
				"haxe.ds.StringMap<Iterator<Int>>",
				"Map<String, Dynamic>",
				"Map<String, Map<Int, Dynamic>>",
				"Array<haxe.ds.StringMap<Dynamic>>",
				"Null<haxe.ds.StringMap<Dynamic>>",
				"Null<Map<Int, Dynamic>>",
				"haxe.ds.List<Int>"
			]) {
				final type = sourceType(source);
				if (projectDeclarationSignature([type], voidType, representations, unexpectedNominal, context) != null)
					throw "unsupported map declaration received a signature: " + source;
			}
			for (source in ["haxe.ds.StringMap<String>", "haxe.ds.IntMap<String>", "Map<String, String>"]) {
				final type = sourceType(source);
				if (projectDeclarationSignature([type], voidType, representations, _ -> TApp("HxMap.string_map", [TIdent("string")]), context) != null)
					throw "an unchecked private name authorized a map signature: " + source;
			}
			final unresolved = switch (sourceType("haxe.ds.StringMap<String>")) {
				case TInst(reference, _): TInst(reference, [Context.makeMonomorph()]);
				case _: throw "missing standard map class";
			};
			if (projectDeclarationSignature([unresolved], voidType, representations, unexpectedNominal, context) != null)
				throw "an unresolved map element received a signature";
		});
		Context.onAfterGenerate(() -> {
			check("roundtrip", "string HxMap.string_map -> string HxMap.string_map");
			check("optional", "Obj.t -> string HxMap.string_map");
			check("integers", "string HxArray.t HxMap.int_map -> string HxArray.t HxMap.int_map");
			check("objects", "(Key.t, string) HxMap.obj_map -> (Key.t, string) HxMap.obj_map");
			check("nested", "string HxMap.int_map HxMap.string_map -> string HxMap.int_map HxMap.string_map");
			check("nullable", "Obj.t -> Obj.t");
		});
	}

	static function sourceType(source:String):Type {
		return Context.typeExpr(Context.parse("(null : " + source + ")", Context.currentPos())).t;
	}

	static function unexpectedNominal(type:Type):OcamlTypeExpr {
		throw "unsupported map storage reached the nominal type mapper";
	}

	/** Checks retained declaration metadata, independently of the final native type checker. */
	static function check(name:String, expected:String):Void {
		final items = OcamlCompiler.instance.moduleChunks.itemsFor("First", "First");
		if (items == null)
			throw "missing First module";
		for (item in items)
			switch (item) {
				case ILet(bindings, _):
					for (binding in bindings)
						if (binding.name == name) {
							if (binding.signature == null)
								throw "missing map signature: " + name;
							final actual = new OcamlASTPrinter().printType(binding.signature);
							if (actual != expected)
								throw "wrong map signature: " + actual + " expected " + expected;
							return;
						}
				case IType(_, _):
			}
		throw "missing map function: " + name;
	}
}
