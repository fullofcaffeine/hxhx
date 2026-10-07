/**
	Expose bodyless metadata signatures without adding executable source methods.

	Implemented methods need an explicit shared implementation identity before
	metadata alternatives can safely route through every native backend. Reject
	that unsupported case instead of presenting an alternative as a host extern.

	Dependency discovery and semantic indexing use the same parsed signatures.
	Each derived declaration retains its authored metadata and owning method's
	position, visibility, and static form. Its generic binders belong to the
	overload, not the primary signature. The source class remains unchanged.
 */
function forClass(source:HxClassDecl, filePath:String):Array<HxFunctionDecl> {
	final declarations = new Array<HxFunctionDecl>();
	for (method in HxClassDecl.getFunctions(source)) {
		declarations.push(method);
		final retained = new Array<String>();
		final overloads = new Array<{source:String, signature:HxParsedFunction}>();
		for (entry in HxFunctionDecl.getMetadata(method)) {
			final parsed = try {
				HxFunctionSyntaxParser.parseOverloadMetadata(entry);
			} catch (error:HxParseError) {
				throw new TyperError(filePath, HxFunctionDecl.getPos(method), error.message);
			};
			if (parsed != null && HxFunctionDecl.getHasBody(method))
				throw new TyperError(filePath, HxFunctionDecl.getPos(method), "Overload metadata on implemented methods requires implementation routing");
			if (parsed != null)
				overloads.push({source: entry, signature: parsed});
			else if (!StringTools.startsWith(entry, HxFunctionTypeParamMetadata.TYPE_PARAMS_PREFIX)
				&& !StringTools.startsWith(entry, HxFunctionTypeParamMetadata.CONSTRAINT_PREFIX))
				retained.push(entry);
		}
		for (alternative in overloads) {
			final parsed = alternative.signature;
			final metadata = retained.concat([alternative.source])
				.concat(HxFunctionTypeParamMetadata.fromParameters(parsed.typeParameters, alternative.source));
			declarations.push(new HxFunctionDecl(HxFunctionDecl.getName(method), HxFunctionDecl.getVisibility(method), HxFunctionDecl.getIsStatic(method), [
				for (argument in parsed.arguments)
					HxFunctionSyntaxParser.methodArgument(argument.declaration)
			], parsed.resultTypeHint, [], "", metadata,
				HxFunctionDecl.getPos(method), HxFunctionDecl.getEndPos(method), "", false));
		}
	}
	return declarations;
}
