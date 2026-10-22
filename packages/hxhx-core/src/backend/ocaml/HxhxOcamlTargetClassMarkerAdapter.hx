package backend.ocaml;

import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan;
import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan.OcamlClassIdentityMarkerDecision;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;

/** Exact native declaration and request that will own a generated instance marker. */
typedef HxhxOcamlClassMarkerInput = {
	final module:TypedModule;
	final typedClass:TypedClass;
	final emissionRole:String;
	final programRevision:String;
	final pipelineRevision:String;
}

/**
	Copy a native typed class into the shared runtime class-marker contract.

	The marker lets Type.getClass identify an allocated record. Its name comes
	from the resolved declaration and its location from the original parser
	range. A class from another module, a generated declaration without a range,
	or an unsupported renamed class cannot borrow that identity. This operation
	does not decide whether the class may be instantiated or execute its body.
 */
function fromTypedClass(input:HxhxOcamlClassMarkerInput):OcamlClassIdentityMarkerDecision {
	if (input == null || input.module == null || input.typedClass == null)
		throw "native OCaml class marker requires a typed module and class";
	input.module.assertBodyRevisionCurrent();
	if (!input.module.getTypedClasses().contains(input.typedClass))
		throw "native OCaml class marker requires a class owned by its typed module";
	final declaration = input.typedClass.getSourceDeclaration();
	final semantic = input.typedClass.getSemanticInfo();
	if (semantic == null || semantic.getIsEnum())
		throw "native OCaml class marker requires a resolved class declaration";
	if (HxClassDecl.getVisibility(declaration) == HxVisibility.Private)
		throw "native OCaml class marker does not yet admit private runtime names";
	for (metadata in HxClassDecl.getMetadata(declaration)) {
		final lexer = new HxLexer(metadata);
		if (lexer.next().kind.match(TOther(64)) && lexer.next().kind.match(TColon))
			switch (lexer.next().kind) {
				case TIdent("native" | "realPath"):
					throw "native OCaml class marker does not yet admit renamed runtime classes";
				case _:
			}
	}
	final range = HxClassDecl.getSourceRange(declaration);
	if (range == null)
		throw "native OCaml class marker requires an original parsed class range";
	final packageParts = semantic.getModulePath().split(".");
	packageParts.pop();
	final className = packageParts.concat([semantic.getShortName()]).join(".");
	return OcamlClassIdentityMarkerPlan.fromTypedInput({
		sourceDeclarationId: className,
		runtimeClassName: className,
		source: {
			file: OcamlLoweredOrigin.normalizeSourcePath(input.module.getParsed().getFilePath()),
			min: range.start,
			max: range.end
		},
		emissionRole: input.emissionRole,
		programRevision: input.programRevision,
		pipelineRevision: input.pipelineRevision
	});
}
