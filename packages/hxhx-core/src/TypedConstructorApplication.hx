/** One exact owner binder and the semantic type supplied at a construction occurrence. */
typedef TypedConstructorOwnerArgument = {
	final parameter:TyTypeParameterId;
	final argument:TyType;
}

/**
	Preserve constructor owner specialization before backend projection.

	The constructed nominal value stays separate from an abstract's backing type
	and from its constructor body's Void completion. For an inherited constructor,
	a checked path retains the applied ancestor and constructor-free classes whose
	field initializers still need execution. These facts apply the declaring owner's
	parameters only. Explicit method parameters still require inference and
	argument conversions before publication of a completed native callable plan.
 */
class TypedConstructorApplication {
	final declaration:TyDeclarationInfo;
	final constructedType:TyType;
	final ownerType:TyType;
	final forwardedTypes:Array<TyType>;
	final ownerArguments:Array<TypedConstructorOwnerArgument>;
	final parameterTypes:Array<TyType>;
	final callableSignature:TyCallableSignature;
	final argumentBinding:Null<TyCallArgumentBinding>;
	final underlyingType:Null<TyType>;
	final multiType:Null<TypedMultiTypeConstruction>;

	public function new(owner:TyNominalInfo, declaration:TyDeclarationInfo, constructedType:TyType,
			?operands:{index:TyperIndex, arguments:Array<HxExpr>, types:Array<TyType>}, ?path:TypedConstructorPath) {
		if (path != null)
			path.assertOwner(owner, constructedType);
		if (owner == null
			|| declaration == null
			|| constructedType == null
			|| constructedType.getNominalIdentity() == null
			|| (path == null && !owner.getIdentity().equals(constructedType.getNominalIdentity()))
			|| !declaration.getOwner().equals(owner.getIdentity())
			|| declaration.getIsStatic()
			|| declaration.getSignature().getName() != "new"
			|| owner.declarationForSignature(declaration.getSignature()) != declaration)
			throw "constructor application requires its exact nominal constructor";
		// The semantic index stores several concrete nominal kinds. Validate the
		// kind before narrowing it to read its exact binders and abstract backing.
		final parameters = if (Std.isOfType(owner, TyAbstractInfo)) {
			(cast owner : TyAbstractInfo).getTypeParameterIds();
		} else if (Std.isOfType(owner, TyClassInfo)) {
			(cast owner : TyClassInfo).getTypeParameterIds();
		} else {
			throw "constructor application requires a class or abstract owner";
		}
		ownerType = path == null ? constructedType : path.getOwnerType();
		forwardedTypes = path == null ? [] : path.getForwardedTypes();
		final arguments = ownerType.getTypeArguments();
		final bindings = TyTypeSubstitution.bind(parameters, arguments, declaration.getIdentity().getCanonicalKey());
		this.declaration = declaration;
		this.constructedType = constructedType;
		this.ownerArguments = [
			for (index in 0...parameters.length)
				{parameter: parameters[index], argument: arguments[index]}
		];
		// Selection and publication consume the same checked body inputs. The
		// original declaration header remains the immutable identity for retention.
		final signature = operands == null ? declaration.getSignature() : operands.index.getMethodBodyResults().signature(declaration);
		this.parameterTypes = [
			for (type in signature.getArgs())
				TyTypeSubstitution.apply(type, bindings)
		];
		callableSignature = TyCallableSignature.fromDeclaration(declaration,
			new TyFunSig(signature.getName(), signature.getIsStatic(), signature.getArgNames(), parameterTypes, signature.getArgOptional(),
				signature.getArgRest(), TyTypeSubstitution.apply(signature.getReturnType(), bindings), signature.getPos()));
		// Freeze shared structural and ancestor evidence while the typing index is
		// available. A backend must not reclassify nominal assignments by shape alone.
		argumentBinding = operands == null ? null : TyCallbackArgumentContext.publish(callableSignature, operands.arguments, operands.types, operands.index);
		this.underlyingType = Std.isOfType(owner,
			TyAbstractInfo) ? TyTypeSubstitution.apply((cast owner : TyAbstractInfo).getUnderlyingType(), bindings) : null;
		multiType = operands == null ? null : switch TyMultiTypeSelection.select(operands.index, constructedType) {
			case Ordinary: null;
			case Rejected(reason): throw reason;
			case Selected(selection): new TypedMultiTypeConstruction(selection, operands.index, operands.arguments, operands.types);
		};
	}

	/** Multi-type abstracts allocate through a selected conversion, never through an empty wrapper constructor. */
	public function getMultiTypeConstruction():Null<TypedMultiTypeConstruction>
		return multiType;

	public function getDeclaration():TyDeclarationInfo
		return declaration;

	public function getConstructedType():TyType
		return constructedType;

	/**
		Instantiate a construction inside an inline body without selecting a different
		constructor or argument layout. Revalidate the exact declaration and ancestry
		against the index, then require the resulting proof to equal substitution of
		the original proof. Multi-type factory reselection needs a separate contract.
	 */
	public function specialize(index:TyperIndex, bindings:haxe.ds.StringMap<TyType>, original:Array<TypedExpr>,
			rewritten:Array<TypedExpr>):TypedConstructorApplication {
		if (multiType != null)
			throw "inline multi-type construction requires retained factory specialization";
		final oldKinds = TypedExpr.operandKinds(original);
		final expected = requireArgumentBinding(TypedExpr.operandTypes(original, oldKinds), oldKinds).substituteTypes(bindings);
		final applied = TyTypeSubstitution.apply(constructedType, bindings);
		final path = TypedConstructorPath.select(index, applied);
		if (path == null
			|| !path.getOwner().getIdentity().equals(declaration.getOwner())
			|| path.getOwnerType().getSemanticKey() != TyTypeSubstitution.apply(ownerType, bindings).getSemanticKey()
			|| CompilerCacheIdentity.encode([for (type in path.getForwardedTypes()) type.getSemanticKey()]) != CompilerCacheIdentity.encode([
				for (type in forwardedTypes)
					TyTypeSubstitution.apply(type, bindings).getSemanticKey()
			]))
			throw "inline construction changed its declaring owner or initializer path";
		final kinds = TypedExpr.operandKinds(rewritten);
		final types = TypedExpr.operandTypes(rewritten, kinds);
		final result = new TypedConstructorApplication(path.getOwner(), declaration, applied,
			{index: index, arguments: rewritten.map(TypedSourceSyntax.expression), types: types}, path);
		if (result.getMultiTypeConstruction() != null
			|| result.requireArgumentBinding(types, kinds).getSemanticKey() != expected.getSemanticKey())
			throw "inline construction changed its checked argument mapping";
		return result;
	}

	/** Constructor parameter binders belong to this applied ancestor, not necessarily the allocated child. */
	public function getOwnerType():TyType
		return ownerType;

	/** Constructor-free classes retain their own initializer obligations in child-to-parent order. */
	public function getForwardedTypes():Array<TyType>
		return forwardedTypes.copy();

	public function getOwnerArguments():Array<TypedConstructorOwnerArgument>
		return ownerArguments.copy();

	public function getParameterTypes():Array<TyType>
		return parameterTypes.copy();

	/** Apply owner types while retaining the selected declaration's omission and rest rules. */
	public function getCallableSignature():TyCallableSignature
		return callableSignature;

	/** Exact operand types and spread shape must still match the evidence published by shared typing. */
	public function requireArgumentBinding(types:Array<TyType>, kinds:Array<TyCallAlignment.TyCallOperandKind>):TyCallArgumentBinding {
		if (argumentBinding == null)
			throw "constructor application has no checked argument binding";
		argumentBinding.assertCurrent(callableSignature.getFunctionType(), types, kinds);
		return argumentBinding;
	}

	/** Null denotes ordinary class construction, not an absent or default abstract payload. */
	public function getUnderlyingType():Null<TyType>
		return underlyingType;

	/** A copied or relabeled node must retain the same applied nominal result. */
	public function assertResult(type:TyType):Void {
		if (type == null || type.getSemanticKey() != constructedType.getSemanticKey())
			throw "constructor application belongs to another applied result";
	}

	public function getSemanticKey():String {
		return CompilerCacheIdentity.encode([
			declaration.getIdentity().getCanonicalKey(),
			constructedType.getSemanticKey(),
			ownerType.getSemanticKey(),
			CompilerCacheIdentity.encode([for (type in forwardedTypes) type.getSemanticKey()]),
			callableSignature.getFunctionType().getSemanticKey(),
			argumentBinding == null ? null : argumentBinding.getSemanticKey(),
			multiType == null ? null : multiType.getSemanticKey(),
			underlyingType == null ? null : underlyingType.getSemanticKey()
		].concat([
			for (entry in ownerArguments)
				CompilerCacheIdentity.encode([entry.parameter.getCanonicalKey(), entry.argument.getSemanticKey()])
			]).concat([for (type in parameterTypes) type.getSemanticKey()]));
	}
}
