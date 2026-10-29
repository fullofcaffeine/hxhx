package backend.ocaml;

/**
	Places the explicitly selected main module at the OCaml emitter's root slot.

	Resolver order may place dependencies first. The bootstrap emitter links its
	first module last and invokes that module's main function, so the target must
	select it from the CLI identity before emission. Reordering this private copy
	preserves the sealed typed bodies and the caller's module order.
**/
function rootFirst(program:MacroExpandedProgram, mainModule:String):MacroExpandedProgram {
	if (mainModule.length == 0)
		throw "OCaml executable requires an explicit main module";
	final modules = program.getTypedModules();
	var rootIndex = -1;
	for (index in 0...modules.length)
		if (modules[index].getSourceOrigin().sourceModulePath == mainModule) {
			rootIndex = index;
			break;
		}
	if (rootIndex < 0)
		throw "OCaml main module is absent from the typed program: " + mainModule;
	if (rootIndex == 0)
		return program;
	final root = modules.splice(rootIndex, 1)[0];
	modules.unshift(root);
	return new MacroExpandedProgram(modules, program.macroMode, program.getGeneratedOcamlModules());
}
