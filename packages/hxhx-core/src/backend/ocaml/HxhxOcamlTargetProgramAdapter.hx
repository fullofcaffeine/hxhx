package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetFieldInitializerFact;
import reflaxe.ocaml.target.OcamlTargetFunctionFact;
import reflaxe.ocaml.target.OcamlTargetProgramRequest;

/**
	Copies one sealed native compiler program into the standalone target contract.

	Only public immutable `TypedModule`, `TypedClass`, `TypedFunction`, and field
	initializer facts are read. No compiler object crosses the returned boundary.
**/
class HxhxOcamlTargetProgramAdapter {
	public static function fromProgram(program:MacroExpandedProgram, mainModuleId:String):OcamlTargetProgramRequest {
		if (program == null)
			throw "native OCaml target program adapter requires a program";
		final modules = program.getTypedModules();
		final projections = [for (module in modules) module.getBackendProjection()];
		final declarations = HxhxOcamlTargetDeclarationAdapter.fromModules(program.getTypedProgramRevision().getCanonicalIdentity(), projections);
		final fieldInitializers = new Array<OcamlTargetFieldInitializerFact>();
		final functions = new Array<OcamlTargetFunctionFact>();
		for (module in modules)
			for (typedClass in module.getTypedClasses()) {
				final owner = typedClass.getSemanticInfo();
				if (owner == null)
					continue;
				for (initializer in typedClass.getFieldInitializers()) {
					final fact = HxhxOcamlTargetFieldInitializerAdapter.fromInitializer(owner, initializer);
					if (fact != null)
						fieldInitializers.push(fact);
				}
				for (fn in typedClass.getFunctions()) {
					final fact = HxhxOcamlTargetFunctionAdapter.fromFunction(owner, fn);
					if (fact != null)
						functions.push(fact);
				}
			}
		return new OcamlTargetProgramRequest(program.getTypedProgramRevision().getCanonicalIdentity(), mainModuleId, declarations, fieldInitializers,
			functions);
	}
}
