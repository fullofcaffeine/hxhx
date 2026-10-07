import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Checks that erased declarations belong to the exact method type parameters. */
class CheckGenericDeclaration {
	public static function install():Void {
		Context.onAfterTyping(_ -> run());
	}

	public static function run():Void {
		final owner = switch (Context.getType("Scope")) {
			case TInst(reference, _): reference.get();
			case _: throw "missing Scope class";
		};
		final within = owner.fields.get().filter(field -> field.name == "within")[0];
		final fail = owner.fields.get().filter(field -> field.name == "fail")[0];
		final registry = new OcamlRepresentationRegistry();
		final context = new CompilationContext();
		switch (TypeTools.follow(within.type)) {
			case TFun(arguments, result):
				final parameters = arguments.map(argument -> argument.t);
				final owned = within.params.map(parameter -> parameter.t);
				final other = fail.params.map(parameter -> parameter.t);
				if (projectDeclarationSignature(parameters, result, registry, unexpectedMapper, context) != null)
					throw "unowned type parameter gained a declaration";
				if (projectDeclarationSignature(parameters, result, registry, unexpectedMapper, context, other) != null)
					throw "another method's same-named parameter gained ownership";
				if (projectDeclarationSignature(parameters, result, registry, _ -> TVar("t"), context, owned) != null)
					throw "erased storage was replaced with an unproved polymorphic variable";
				final signature = projectDeclarationSignature(parameters, result, registry, _ -> TIdent("Obj.t"), context, owned);
				if (signature == null
					|| new OcamlASTPrinter().printType(signature.parameters[0]) != "unit -> Obj.t"
						|| new OcamlASTPrinter().printType(signature.result) != "Obj.t")
					throw "owned generic callback lost its erased declaration";
				for (unsupported in [
					Context.resolveType(macro :Dynamic, Context.currentPos()),
					Context.makeMonomorph()
				])
					if (projectDeclarationSignature([unsupported], result, registry, unexpectedMapper, context, owned) != null)
						throw "unknown type gained erased-method permission";
			case _:
				throw "within has no function type";
		}
		for (nullable in [
			Context.resolveType(macro :Null<Int>, Context.currentPos()),
			Context.resolveType(macro :Null<Bool>, Context.currentPos())
		]) {
			final signature = projectDeclarationSignature([nullable], nullable, registry, _ -> TIdent("Obj.t"), context);
			if (signature == null
				|| new OcamlASTPrinter().printType(signature.parameters[0]) != "Obj.t"
					|| new OcamlASTPrinter().printType(signature.result) != "Obj.t")
				throw "nullable scalar lost its existing Obj.t declaration";
			if (projectDeclarationSignature([nullable], nullable, registry, _ -> TIdent("int"), context) != null)
				throw "nullable scalar accepted storage that cannot retain null";
		}
		Sys.println("GENERIC_DECLARATION_OWNERSHIP:PASS");
	}

	static function unexpectedMapper(type:Type):OcamlTypeExpr {
		throw "unsupported declaration reached the nominal mapper";
	}
}
