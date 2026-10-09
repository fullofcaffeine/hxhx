import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import reflaxe.helpers.ClassFieldHelper;
import reflaxe.ocaml.target.HaxeOcamlTargetFunctionAdapter;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;

/** Capture authored constructors and methods independently from the native frontend. */
class StockInstanceValuesMacro {
	public static macro function expected():Expr {
		final rows = new Array<Expr>();
		for (moduleType in Context.getModule("Main"))
			switch (moduleType) {
				case TInst(reference, _):
					final owner = reference.get();
					final fields = owner.fields.get().map(field -> {field: field, isStatic: false});
					if (owner.constructor != null)
						fields.push({field: owner.constructor.get(), isStatic: false});
					for (field in owner.statics.get())
						fields.push({field: field, isStatic: true});
					for (entry in fields) {
						final data = ClassFieldHelper.findFuncData(entry.field, owner, entry.isStatic);
						if (data == null)
							continue;
						final fact = HaxeOcamlTargetFunctionAdapter.fromSourceBeforePreprocessing(data);
						final admitted = fact != null;
						final identity = fact == null ? "" : fact.getCanonicalIdentity();
						final syntax = fact == null ? "" : new OcamlASTPrinter().printExpr(OcamlTargetFunctionLowerer.build(fact));
						rows.push(macro {
							owner: $v{owner.name},
							name: $v{entry.field.name},
							admitted: $v{admitted},
							identity: $v{identity},
							syntax: $v{syntax}
						});
					}
				case _:
			}
		return macro $a{rows};
	}
}
