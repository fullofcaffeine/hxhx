import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import reflaxe.ocaml.target.HaxeOcamlTargetDeclarationAdapter;

/** Copy the same authored class headers through the public upstream macro API. */
class StockClassKindsMacro {
	public static macro function expected():Expr {
		final types:Array<ModuleType> = [];
		for (type in Context.getModule("ClassKinds"))
			switch (type) {
				case TInst(reference, _):
					types.push(TClassDecl(reference));
				case _:
					throw "class-header fixture contains an unexpected declaration kind";
			}
		final request = HaxeOcamlTargetDeclarationAdapter.fromModuleTypes("stock-class-headers", types);
		final rows = new Array<Expr>();
		for (cls in request.copyClasses()) {
			final facts = new Array<Null<String>>();
			cls.addIdentity(facts);
			rows.push(macro {
				name: $v{cls.canonicalIdentity},
				identity: $v{cls.getCanonicalIdentity()},
				facts: $v{haxe.Json.stringify(facts)},
				isInterface: $v{cls.isInterface},
				isExtern: $v{cls.isExtern},
				interfaces: $v{cls.copyInterfaceTypeDisplays().join("|")}
			});
		}
		return macro $a{rows};
	}
}
