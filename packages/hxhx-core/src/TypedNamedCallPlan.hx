/** Prepare source-aligned contexts from the winning method order, then validate converted operands exactly once. */
class TypedNamedCallPlan {
	final declaration:TyDeclarationInfo;
	final signature:TyFunSig;
	final order:TyMethodArgumentOrder;
	final parameterTypes:Array<TyType>;
	final sources:Array<HxExpr>;
	final index:TyperIndex;
	final extensionProvider:Null<TyNominalTypeId>;

	public function new(input:{
		declaration:TyDeclarationInfo,
		signature:TyFunSig,
		order:TyMethodArgumentOrder,
		parameters:Array<TyType>,
		sources:Array<HxExpr>,
		index:TyperIndex,
		extensionProvider:Null<TyNominalTypeId>
	}) {
		declaration = input.declaration;
		signature = input.signature;
		order = input.extensionProvider == null ? input.order : input.order.withoutReceiver();
		parameterTypes = input.extensionProvider == null ? input.parameters.copy() : input.parameters.slice(1);
		sources = input.sources.copy();
		index = input.index;
		extensionProvider = input.extensionProvider;
	}

	public function getExpectedArguments():Array<TyType>
		return order.sourceContexts(parameterTypes);

	/** The extension receiver remains in the callee and is supplied once before these explicit operands. */
	public function publish(values:Array<TypedExpr>, result:TyType):TypedNamedCallBinding {
		final offset = extensionProvider == null ? 0 : 1;
		final declared = TyCallableSignature.fromDeclaration(declaration, signature).getParameters().slice(offset);
		final sourceDeclaration = declaration.getSourceDeclaration();
		final sourceArguments = sourceDeclaration == null ? [] : HxFunctionDecl.getArgs(sourceDeclaration);
		final slots = order.getSlots();
		if (declared.length != parameterTypes.length)
			throw "named call parameter contexts changed after selection";
		final parameters = [
			for (slot in 0...declared.length) {
				final source = declared[slot];
				var type = parameterTypes[slot];
				// Dynamic does not solve an omitted declaration parameter in Haxe.
				// Retain that unresolved declaration, but record this invocation's
				// explicit Dynamic transport type. No other Unknown is admitted.
				if (type.isUnknown()
					&& !source.isRest
					&& sourceDeclaration != null
					&& HxFunctionDecl.getHasBody(sourceDeclaration)
					&& slot + offset < sourceArguments.length) {
					final hint = HxFunctionArg.getTypeHint(sourceArguments[slot + offset]);
					if (hint == null || StringTools.trim(hint).length == 0)
						switch slots[slot] {
							case Supplied(index) if (index < values.length && values[index].getType().isDynamic()):
								type = values[index].getType();
							case _:
						}
				}
				final elements = type.getTypeArguments();
				if (source.isRest && elements.length != 1) throw "named call rest context requires its declared container";
				{
					name: source.name,
					type: source.isRest ? elements[0] : type,
					isOptional: source.isOptional,
					isRest: source.isRest,
					metadata: source.metadata
				};
			}
		];
		final callable = TyCallableSignature.fromFunctionValue(TyType.functionSignature(parameters, result));
		final kinds = TypedExpr.operandKinds(values);
		final types = TypedExpr.operandTypes(values, kinds);
		return new TypedNamedCallBinding(declaration, extensionProvider, TyCallbackArgumentContext.publishSelected(callable, sources, types, index, order));
	}
}
