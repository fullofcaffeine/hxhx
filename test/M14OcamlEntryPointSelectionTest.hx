/** Checks that dependency order cannot select the OCaml program entry point. */
class M14OcamlEntryPointSelectionTest {
	static function expectRejected(program:MacroExpandedProgram, mainModule:String):Void {
		var rejected = false;
		try {
			backend.ocaml.OcamlEntryPointSelection.rootFirst(program, mainModule);
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw "missing entry module was silently replaced by a dependency";
	}

	static function main():Void {
		final resolved = [
			for (pack in ["a", "z"])
				new ResolvedModule(pack + ".Entry", pack + "/Entry.hx",
					ParserStage.parse("package " + pack + "; class Entry { public static function main():Void {} }", pack + "/Entry.hx"))
		];
		final index = TyperIndex.build(resolved);
		final modules = [for (module in resolved) TyperStage.typeResolvedModule(module, index)];
		final generated:MacroExpandedModule.GeneratedOcamlModule = {name: "Generated", source: "let value = 1"};
		final original = new MacroExpandedProgram(modules, true, [generated]);
		final selected = backend.ocaml.OcamlEntryPointSelection.rootFirst(original, "z.Entry");
		if (selected.getTypedModules()[0] != modules[1] || selected.getTypedModules()[1] != modules[0])
			throw "the fully qualified entry module was not selected";
		if (original.getTypedModules()[0] != modules[0])
			throw "entry selection mutated the caller's module order";
		if (!selected.macroMode || selected.getGeneratedOcamlModules()[0] != generated)
			throw "entry selection lost macro artifacts";
		if (selected.getTypedProgramRevision().getCanonicalIdentity() != original.getTypedProgramRevision().getCanonicalIdentity())
			throw "entry selection changed the sealed semantic program revision";
		expectRejected(original, "Entry");
		expectRejected(original, "missing.Entry");
		expectRejected(original, "");
		Sys.println("OCAML_ENTRY_POINT_SELECTION:PASS");
	}
}
