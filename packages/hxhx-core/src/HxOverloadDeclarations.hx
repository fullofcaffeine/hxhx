/** An alternate callable signature retains the exact authored implementation owner. */
typedef HxIndexedFunctionDeclaration = {
	final declaration:HxFunctionDecl;
	final implementation:HxFunctionDecl;
};

/**
	Expose metadata signatures without adding executable source methods.
	Dependency discovery and indexing consume the same parsed facts. Each
	alternative retains its own binders and the exact primary source method.
	The source class and its implementation bodies remain unchanged.
 */
function forClass(source:HxClassDecl, filePath:String):Array<HxIndexedFunctionDeclaration> {
	final declarations = new Array<HxIndexedFunctionDeclaration>();
	for (method in HxClassDecl.getFunctions(source)) {
		declarations.push({declaration: method, implementation: method});
		final retained = new Array<String>();
		final overloads = new Array<{source:String, signature:HxParsedFunction}>();
		for (entry in HxFunctionDecl.getMetadata(method)) {
			final parsed = try {
				HxFunctionSyntaxParser.parseOverloadMetadata(entry);
			} catch (error:HxParseError) {
				throw new TyperError(filePath, HxFunctionDecl.getPos(method), error.message);
			};
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
			declarations.push({
				implementation: method,
				declaration: new HxFunctionDecl(HxFunctionDecl.getName(method), HxFunctionDecl.getVisibility(method), HxFunctionDecl.getIsStatic(method), [
					for (argument in parsed.arguments)
						HxFunctionSyntaxParser.methodArgument(argument.declaration)
				], parsed.resultTypeHint, [], "", metadata,
					HxFunctionDecl.getPos(method), HxFunctionDecl.getEndPos(method), "", false)
			});
		}
	}
	return declarations;
}
