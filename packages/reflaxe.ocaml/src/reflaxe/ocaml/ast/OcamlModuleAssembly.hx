package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlModuleGroups.plan as planGroups;
import reflaxe.ocaml.ast.OcamlModuleGroups.OcamlModuleDependencyNode;
import reflaxe.ocaml.ast.OcamlRecursiveModuleCheck;
import reflaxe.ocaml.ast.OcamlRecursiveModuleCheck.checkRecursiveModule;
import reflaxe.ocaml.runtimegen.RuntimeUsageCollector;

/** Headers accompany compiler-owned declarations; framework-supplied text has no graph facts. */
enum OcamlModulePart {
	ModuleDeclarations(header:String, items:Array<OcamlModuleItem>);
	OpaqueModuleText(text:String);
}

/** One existing compilation unit, including its carrier and static-storage preludes. */
typedef OcamlModuleAssemblyInput = {
	final name:String;
	final parts:Array<OcamlModulePart>;
}

/**
	Plans complete module bodies before any compilation unit is published.

	A recursive group lives in its alphabetically first existing unit. That file
	re-exports its original module; other members keep their filenames and alias
	the corresponding nested module. Existing callers and registry paths therefore
	keep the same type and value identities without expression rewriting.
	Functions and primitive literals require fully visible declarations. Every
	cycle must pass through a module exporting only functions, so OCaml can
	initialize the group without reading an unfinished value.
	Invalid declarations report one failure per affected module in graph order.
	All declaration and initialization checks finish before interface runtime
	references are activated or output is rendered.
	Local function dependencies are ordered before inter-module planning.
	Already valid acyclic output retains its original text and part order.
**/
function assembleModules(source:Array<OcamlModuleAssemblyInput>, printer:OcamlASTPrinter,
		?signatureTypeForOutput:(OcamlTypeExpr, String) -> OcamlTypeExpr):Map<String, String> {
	final input:Array<OcamlModuleAssemblyInput> = [
		for (module in source)
			{name: module.name, parts: OcamlModuleValues.order(module.name, module.parts)}
	];
	final byName:Map<String, OcamlModuleAssemblyInput> = [];
	final itemsByName:Map<String, Array<OcamlModuleItem>> = [];
	final valueNodes:Array<OcamlModuleDependencyNode> = [];
	var opaque = false;
	final nodes = [
		for (module in input) {
			byName.set(module.name, module);
			final items:Array<OcamlModuleItem> = [];
			for (part in module.parts)
				switch (part) {
					case ModuleDeclarations(_, declarations):
						for (declaration in declarations)
							items.push(declaration);
					case OpaqueModuleText(text):
						if (text.length > 0)
							opaque = true;
				}
			itemsByName.set(module.name, items);
			final references = OcamlModuleReferences.collect(items);
			valueNodes.push({name: module.name, dependencies: references.functionModules.concat(references.initializationModules)});
			{
				name: module.name,
				dependencies: references.functionModules.concat(references.initializationModules).concat(references.typeModules)
			};
		}
	];
	final graph = planGroups(nodes);
	function partsFor(name:String):Array<OcamlModulePart> {
		final module = byName.get(name);
		if (module == null)
			throw "Missing module assembly owner: " + name;
		return module.parts;
	}
	final signatures:Map<String, Array<OcamlModuleSignatureItem>> = [];
	final literalModules:Map<String, Bool> = [];
	final problems:Array<String> = [];
	for (group in graph.groups) {
		if (!group.recursive)
			continue;
		if (opaque)
			throw "reflaxe.ocaml [ocaml-module-cycle:opaque-output]: recursive grouping requires structured declarations for every emitted module";
		for (name in group.members) {
			final items = itemsByName.get(name);
			if (items == null)
				throw "Missing recursive module declarations: " + name;
			switch (checkRecursiveModule(items)) {
				case RecursiveModuleRejected(problem):
					problems.push(name + ": " + Std.string(problem));
				case RecursiveModuleReady(signature, functionsOnly):
					if (!functionsOnly)
						literalModules.set(name, true);
					signatures.set(name, signature);
			}
		}
	}
	// One expensive generation attempt should reveal independent module failures.
	// Keep the complete group rejected, and do not activate output references yet.
	if (problems.length > 0)
		throw "reflaxe.ocaml [ocaml-module-cycle:unsupported-initialization]: " + problems.join("\n");
	// Remove function-only modules, which OCaml can initialize with delayed
	// placeholders. A remaining cycle has no safe initialization anchor.
	// Type-only references group declarations but impose no runtime order.
	final unsafeNodes = [
		for (node in valueNodes)
			if (literalModules.exists(node.name)) {
				name: node.name,
				dependencies: node.dependencies.filter(name -> literalModules.exists(name))
			}
	];
	for (group in planGroups(unsafeNodes).groups)
		if (group.recursive)
			throw "reflaxe.ocaml [ocaml-module-cycle:unsafe-literal-cycle]: " + group.members.join(", ");

	// Only validated declarations may spend checked runtime references on their
	// interfaces. Preserve the original graph order for accepted programs.
	for (group in graph.groups)
		if (group.recursive)
			for (name in group.members) {
				final signature = signatures.get(name);
				if (signature == null)
					throw "Missing recursive module signature: " + name;
				signatures.set(name, prepareSignatureTypes(signature, name, byName, signatureTypeForOutput));
			}

	final output:Map<String, String> = [];
	for (group in graph.groups) {
		final owner = group.members[0];
		if (!group.recursive) {
			output.set(owner, renderParts(partsFor(owner), printer));
			continue;
		}
		final declarations:Array<String> = [];
		for (index in 0...group.members.length) {
			final name = group.members[index];
			final signature = signatures.get(name);
			if (signature == null)
				throw "Missing recursive module signature: " + name;
			final header = (index == 0 ? "module rec " : "and ") + name + " : sig\n";
			final signatureText = [
				for (item in signature)
					switch (item) {
						case SValue(valueName, type):
							"val " + valueName + " : " + printer.printType(type);
						case SType(types, isRec):
							printer.printItem(IType(types, isRec));
					}
			].join("\n");
			declarations.push(header + signatureText + "\nend = struct\n" + renderParts(partsFor(name), printer) + "\nend");
			if (name != owner)
				output.set(name, "include " + owner + "." + name);
		}
		output.set(owner, declarations.join("\n") + "\n\ninclude " + owner);
	}
	return output;
}

private function renderParts(parts:Array<OcamlModulePart>, printer:OcamlASTPrinter):String {
	return [
		for (part in parts)
			switch (part) {
				case ModuleDeclarations(header, items):
					header + printer.printModule(items);
				case OpaqueModuleText(text):
					text;
			}
	].join("\n\n");
}

/**
	Retains each interface type at its exact output site before printing.

	Plain private-runtime names remain invalid. Checked references need the
	compiler's final-output authority to account for their additional appearance.
	The callback receives only selected types; it cannot infer missing signatures.
**/
private function prepareSignatureTypes(signature:Array<OcamlModuleSignatureItem>, name:String, ownedModules:Map<String, OcamlModuleAssemblyInput>,
		signatureTypeForOutput:Null<(OcamlTypeExpr, String) -> OcamlTypeExpr>):Array<OcamlModuleSignatureItem> {
	function prepare(type:OcamlTypeExpr, role:String):OcamlTypeExpr {
		OcamlASTTraversal.walkTypePre(type, current -> switch (current) {
			case TIdent(symbol), TApp(symbol, _):
				RuntimeUsageCollector.collectTypeExpr(TIdent(symbol), candidate -> {
					if (!ownedModules.exists(candidate))
						throw "reflaxe.ocaml [ocaml-module-cycle:signature-runtime-copy-required]: " + name;
				});
			case TRuntimeIdent(_), TRuntimeApp(_, _):
				if (signatureTypeForOutput == null) throw "reflaxe.ocaml [ocaml-module-cycle:signature-runtime-copy-required]: " + name;
			case _:
		});
		return signatureTypeForOutput == null ? type : signatureTypeForOutput(type, "module-signature:" + name + ":" + role);
	}
	return [
		for (item in signature)
			switch (item) {
				case SValue(valueName, type):
					SValue(valueName, prepare(type, "value:" + valueName));
				case SType(declarations, isRec):
					SType([
						for (declaration in declarations) {
							final role = "type:" + declaration.name;
							{
								name: declaration.name,
								params: declaration.params,
								kind: switch (declaration.kind) {
									case Alias(type): Alias(prepare(type, role));
									case Record(fields): Record([
											for (field in fields)
												{
													name: field.name,
													isMutable: field.isMutable,
													typ: prepare(field.typ, role + ":field:" + field.name)
												}
										]);
									case Variant(constructors): Variant([
											for (constructor in constructors)
												{
													name: constructor.name,
													args: [
														for (index in 0...constructor.args.length)
															prepare(constructor.args[index], role + ":constructor:" + constructor.name + ":argument:" + index)
													]
												}
										]);
								}
							};
						}
					], isRec);
			}
	];
}
