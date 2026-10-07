import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlBuilder;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan;

/** Tests the ordinary argument conversion without a generic callback or complete call plan. */
@:access(reflaxe.ocaml.ast.OcamlBuilder)
class CheckNullableBooleanAssignment {
	public static function install():Void {
		Context.onAfterTyping(_ -> {
			final builder = new OcamlBuilder(new CompilationContext(), scalarType, new OcamlFunctionPlanRegistry(), new OcamlRepresentationRegistry(),
				new OcamlStaticStoragePlan());
			final printer = new OcamlASTPrinter();
			final nullable = Context.resolveType(macro :Null<Bool>, Context.currentPos());
			final dynamicType = Context.resolveType(macro :Dynamic, Context.currentPos());
			final absent = Context.typeExpr(macro(null : Null<Bool>));
			if (printer.printExpr(builder.coerceForAssignment(nullable, absent)) != "HxRuntime.hx_null")
				throw "nullable Boolean null lost its sentinel identity";
			for (source in [macro false, macro true]) {
				final value = Context.typeExpr(source);
				final literal = switch (value.expr) {
					case TConst(TBool(flag)): flag ? "true" : "false";
					case _: throw "expected a Boolean constant";
				};
				final nullableOutput = printer.printExpr(builder.coerceForAssignment(nullable, value));
				if (nullableOutput != 'Obj.repr $literal')
					throw 'nullable Boolean argument uses the wrong storage: $nullableOutput';
				final dynamicOutput = printer.printExpr(builder.coerceForAssignment(dynamicType, value));
				if (dynamicOutput != 'HxRuntime.box_bool $literal')
					throw 'Dynamic Boolean argument lost its tagged storage: $dynamicOutput';
			}
			Sys.println("NULLABLE_BOOLEAN_ARGUMENT_STORAGE:PASS");
		});
	}

	/** Supplies only the three real storage types needed by this reduced assignment test. */
	static function scalarType(type:Type):OcamlTypeExpr {
		return switch (type) {
			case TAbstract(reference, [_]) if (reference.get().pack.length == 0 && reference.get().name == "Null"): TIdent("Obj.t");
			case TAbstract(reference, []) if (reference.get().pack.length == 0 && reference.get().name == "Bool"): TIdent("bool");
			case TDynamic(_): TIdent("Obj.t");
			case _: throw "unexpected type at the reduced assignment boundary";
		};
	}
}
