import haxe.macro.Context;
import ClassMarkerObservation.describeRequirements;
import haxe.macro.Expr;
import haxe.macro.Type;
import reflaxe.ocaml.target.HaxeOcamlTargetDeclarationAdapter;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan;
import reflaxe.ocaml.target.OcamlTargetClassMarker.lowerClassMarker;

/** Copy the same authored class headers through the public upstream macro API. */
class StockClassKindsMacro {
	/** Observe actual upstream class positions and target syntax for both allocation roles. */
	public static macro function markers():Expr {
		final rows = new Array<Expr>();
		for (type in Context.getModule("ClassKinds"))
			switch (type) {
				case TInst(reference, _):
					final cls = reference.get();
					final runtimeName = cls.pack.concat([cls.name]).join(".");
					for (role in [
						OcamlClassIdentityMarkerPlan.CONSTRUCTOR_ROLE,
						OcamlClassIdentityMarkerPlan.EMPTY_INSTANCE_ROLE
					]) {
						final marker = OcamlClassIdentityMarkerPlan.seal(cls, runtimeName, role, "class-headers-program", "class-headers-pipeline");
						final syntax = new OcamlASTPrinter().printExpr(lowerClassMarker(marker, "portable").expression);
						rows.push(macro {
							name: $v{marker.sourceDeclarationId},
							role: $v{role},
							id: $v{marker.id},
							revision: $v{marker.revision},
							file: $v{marker.source.file},
							start: $v{marker.source.min},
							end: $v{marker.source.max},
							syntax: $v{syntax},
							requirements: $v{describeRequirements(lowerClassMarker(marker, "portable").runtimeRequirements)}
						});
					}
				case _:
					throw "class-marker fixture contains an unexpected declaration kind";
			}
		return macro $a{rows};
	}

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
