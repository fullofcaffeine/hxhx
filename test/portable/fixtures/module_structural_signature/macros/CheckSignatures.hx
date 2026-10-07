import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassPlanner;

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
				"Array<Dynamic>",
				"Array<Array<Dynamic>>",
				"Null<Array<Dynamic>>",
				"Array<Iterator<Int>>",
				"Array<haxe.io.Bytes>",
				"Dynamic",
				"sys.FileStat",
				"haxe.io.Input"
			]) {
				final expression = Context.parse("(null : " + source + ")", Context.currentPos());
				final type = Context.typeExpr(expression).t;
				if (projectDeclarationSignature([type], voidType, representations, unexpectedNominal, context) != null)
					throw "unsupported declaration received a signature: " + source;
			}
			// Nullable primitives use the existing boxed carrier so null stays distinct
			// from zero and false. A scalar mapping must not authorize this boundary.
			for (source in ["Null<Int>", "Null<Bool>"]) {
				final type = Context.typeExpr(Context.parse("(null : " + source + ")", Context.currentPos())).t;
				final signature = projectDeclarationSignature([type], type, representations, _ -> TIdent("Obj.t"), context);
				if (signature == null
					|| new OcamlASTPrinter().printType(signature.parameters[0]) != "Obj.t"
						|| new OcamlASTPrinter().printType(signature.result) != "Obj.t")
					throw "nullable primitive lost its boxed declaration carrier: " + source;
				for (carrier in ["int", "bool", "unit"])
					if (projectDeclarationSignature([type], type, representations, _ -> TIdent(carrier), context) != null)
						throw "nullable primitive accepted an unboxed declaration carrier: " + source;
			}
			if (projectDeclarationSignature([Context.makeMonomorph()], voidType, representations, unexpectedNominal, context) != null)
				throw "unresolved type received a signature";
			final unresolvedArray = switch (Context.getType("Array")) {
				case TInst(reference, _): TInst(reference, [Context.makeMonomorph()]);
				case _: throw "missing standard Array declaration";
			};
			if (projectDeclarationSignature([unresolvedArray], voidType, representations, unexpectedNominal, context) != null)
				throw "an unresolved array element received a signature";
			final arrayType = Context.typeExpr(Context.parse("(null : Array<Int>)", Context.currentPos())).t;
			if (projectDeclarationSignature([arrayType], voidType, representations, _ -> TIdent("HxArray.t"), context) != null)
				throw "a plain private type name authorized an array signature";
			context.virtualTypesComputed = true;
			if (projectDeclarationSignature([Context.getType("haxe.io.Bytes")], voidType, representations, unexpectedNominal, context) != null)
				throw "private Bytes storage received a direct record signature";
			context.dispatchTypes.set("Token", true);
			final tokenType = Context.getType("Token");
			final tokenClass = switch (tokenType) {
				case TInst(reference, []): reference.get();
				case _: throw "missing Token class";
			};
			if (OcamlMonomorphicClassPlanner.hasDirectRecordLayout(tokenClass, context))
				throw "a dispatch class gained direct-field optimization permission";
			final dispatchDeclaration = projectDeclarationSignature([tokenType], voidType, representations, _ -> TIdent("Token.t"), context);
			if (dispatchDeclaration == null || new OcamlASTPrinter().printType(dispatchDeclaration.parameters[0]) != "Token.t")
				throw "a dispatch declaration lost its existing named record type";
		});
		Context.onAfterGenerate(() -> {
			check("Token", "create", "int -> t");
			check("Token", "getLinked", "t -> unit -> t");
			check("Token", "setLinked", "t -> t -> unit");
			check("Token", "label", "t -> string -> string");
			check("Token", "getValues", "t -> unit -> int HxArray.t");
			check("Token", "append", "t -> int HxArray.t -> unit");
			check("First", "copy", "Obj.t -> Obj.t");
			check("First", "make", "int -> Obj.t");
			check("First", "change", "Obj.t -> int -> unit");
			check("First", "withToken", "Obj.t -> Token.t -> Obj.t");
			check("First", "scopes", "Obj.t -> Token.t HxArray.t HxArray.t -> Token.t HxArray.t HxArray.t");
			check("First", "identity", "Token.t HxArray.t HxArray.t -> Token.t HxArray.t HxArray.t");
			check("Second", "scopes", "Token.t HxArray.t HxArray.t -> Token.t HxArray.t HxArray.t");
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
