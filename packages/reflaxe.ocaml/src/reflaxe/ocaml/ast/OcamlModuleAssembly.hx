package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlModuleGroups.plan as planGroups;
import reflaxe.ocaml.ast.OcamlFunctionModuleCheck;
import reflaxe.ocaml.ast.OcamlFunctionModuleCheck.checkFunctionModule;
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
	Only function-only groups with fully visible declarations are admitted here.
	Acyclic output retains its original text and part order.
**/
function assembleModules(input:Array<OcamlModuleAssemblyInput>, printer:OcamlASTPrinter):Map<String, String> {
	final byName:Map<String, OcamlModuleAssemblyInput> = [];
	final itemsByName:Map<String, Array<OcamlModuleItem>> = [];
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
	for (group in graph.groups) {
		if (!group.recursive)
			continue;
		if (opaque)
			throw "reflaxe.ocaml [ocaml-module-cycle:opaque-output]: recursive grouping requires structured declarations for every emitted module";
		for (name in group.members) {
			final items = itemsByName.get(name);
			if (items == null)
				throw "Missing recursive module declarations: " + name;
			switch (checkFunctionModule(items)) {
				case FunctionModuleRejected(problem):
					throw "reflaxe.ocaml [ocaml-module-cycle:unsupported-initialization]: " + name + ": " + Std.string(problem);
				case FunctionModuleReady(signature):
					requirePlainSignatureTypes(signature, name, byName);
					signatures.set(name, signature);
			}
		}
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

/** Duplicating a private type token in a signature needs a separate checked output identity. */
private function requirePlainSignatureTypes(signature:Array<OcamlModuleSignatureItem>, name:String, ownedModules:Map<String, OcamlModuleAssemblyInput>):Void {
	function check(type:OcamlTypeExpr):Void {
		RuntimeUsageCollector.collectTypeExpr(type, candidate -> {
			if (!ownedModules.exists(candidate))
				throw "reflaxe.ocaml [ocaml-module-cycle:signature-runtime-copy-required]: " + name;
		});
		OcamlASTTraversal.walkTypePre(type, current -> switch (current) {
			case TRuntimeIdent(_), TRuntimeApp(_, _):
				throw "reflaxe.ocaml [ocaml-module-cycle:signature-runtime-copy-required]: " + name;
			case _:
		});
	}
	for (item in signature)
		switch (item) {
			case SValue(_, type):
				check(type);
			case SType(declarations, _):
				for (declaration in declarations)
					switch (declaration.kind) {
						case Alias(type): check(type);
						case Record(fields): for (field in fields)
								check(field.typ);
						case Variant(constructors): for (constructor in constructors)
								for (type in constructor.args)
									check(type);
					}
		}
}
