import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Checks retained export types and rejects unsupported storage before native compilation. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckSignatures {
	public static function install():Void {
		Context.onAfterTyping(_ -> {
			final voidType = Context.getType("Void");
			final representations = new OcamlRepresentationRegistry();
			final context = new CompilationContext();
			for (source in [
				"Iterator<Int>",
				"{key:Int, value:Int}",
				"Array<Int>",
				"Dynamic",
				"sys.FileStat",
				"haxe.io.Input"
			]) {
				final expression = Context.parse("(null : " + source + ")", Context.currentPos());
				final type = Context.typeExpr(expression).t;
				if (projectDeclarationSignature([type], voidType, representations, unexpectedNominal, context) != null)
					throw "unsupported declaration received a signature: " + source;
			}
			if (projectDeclarationSignature([Context.makeMonomorph()], voidType, representations, unexpectedNominal, context) != null)
				throw "unresolved type received a signature";
			context.virtualTypesComputed = true;
			if (projectDeclarationSignature([Context.getType("haxe.io.Bytes")], voidType, representations, unexpectedNominal, context) != null)
				throw "private Bytes storage received a direct record signature";
			context.dispatchTypes.set("Token", true);
			if (projectDeclarationSignature([Context.getType("Token")], voidType, representations, unexpectedNominal, context) != null)
				throw "a class marked for subtype dispatch received a direct record signature";
		});
		Context.onAfterGenerate(() -> {
			check("Token", "create", "int -> t");
			check("First", "copy", "Obj.t -> Obj.t");
			check("First", "make", "int -> Obj.t");
			check("First", "change", "Obj.t -> int -> unit");
			check("First", "withToken", "Obj.t -> Token.t -> Obj.t");
			check("Second", "copy", "Obj.t -> Obj.t");
			check("Second", "update", "Obj.t -> Obj.t");
		});
	}

	static function unexpectedNominal(type:Type):OcamlTypeExpr {
		throw "unsupported storage reached the nominal type mapper";
	}

	/** Retained syntax, rather than generated text, owns the exported function type. */
	static function check(moduleId:String, name:String, expected:String):Void {
		final items = OcamlCompiler.instance.moduleChunks.itemsFor(moduleId, moduleId);
		if (items == null)
			throw "missing module syntax: " + moduleId;
		for (item in items)
			switch (item) {
				case ILet(bindings, _):
					for (binding in bindings)
						if (binding.name == name) {
							if (binding.signature == null)
								throw "missing structural signature: " + moduleId + "." + name;
							final actual = new OcamlASTPrinter().printType(binding.signature);
							if (actual != expected)
								throw "wrong structural signature: " + actual + " expected " + expected;
							return;
						}
				case IType(_, _):
			}
		throw "missing function: " + moduleId + "." + name;
	}
}
