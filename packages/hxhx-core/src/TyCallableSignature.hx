/**
	A common parameter view for a selected declaration or an ordinary function value.

	The view stores rest element types, names, optionality, and metadata. Concrete
	defaults remain on the declaration. Function values have no synthetic declaration
	or owned method binders. This is an input to call checking, not a validated call:
	open generic types, conversions, receiver roles, and operand binding still need
	their own proof before a typed call can be published.
 */
class TyCallableSignature {
	final declaration:Null<TyDeclarationInfo>;
	final functionType:TyType;
	final methodTypeParameters:Array<TyTypeParameterId>;

	function new(functionType:TyType, declaration:Null<TyDeclarationInfo>) {
		if (functionType == null || !functionType.isFunction() || functionType.getFunctionReturn() == null)
			throw "callable signature requires a function type with a result";
		this.functionType = functionType;
		this.declaration = declaration;
		methodTypeParameters = declaration == null ? [] : declaration.getTypeParameterIds();
	}

	/** Reveal a recursive callable without replacing its stored value type or inventing a declaration. */
	public static function fromFunctionValue(type:TyType):TyCallableSignature
		return new TyCallableSignature(TyAliasExpansion.revealNonNullable(type), null);

	/** Retain written omission rules when inference supplies a source function's argument and result types. */
	public static function sourceFunctionType(names:Array<String>, source:Null<HxLambdaSignature>, arguments:Array<TyType>, result:TyType):TyType {
		final written = source == null ? null : source.getParameters();
		if (names.length != arguments.length || (written != null && written.length != names.length))
			throw "source callable parameter facts differ from its inferred arguments";
		return TyType.functionSignature([
			for (index in 0...arguments.length) {
				final parameter = written == null ? null : written[index];
				final rest = parameter != null && parameter.isRest;
				final components = arguments[index].getTypeArguments();
				if (rest && components.length != 1) throw "source rest parameter requires its body container's element type";
				{
					name: names[index],
					type: rest ? components[0] : arguments[index],
					isOptional: parameter != null && (parameter.isOptional || parameter.hasDefault),
					isRest: rest,
					metadata: []
				};
			}
		], result);
	}

	/** Preserve declaration metadata and calling rules when a checked body supplies inferred types. */
	public static function fromDeclaration(declaration:TyDeclarationInfo, ?checkedSignature:TyFunSig):TyCallableSignature {
		if (declaration == null)
			throw "declared callable signature requires an exact declaration";
		final signature = checkedSignature == null ? declaration.getSignature() : checkedSignature;
		if (signature.getName() != declaration.getSignature().getName()
			|| signature.getIsStatic() != declaration.getIsStatic()
			|| signature.getArgs().length != declaration.getSignature().getArgs().length)
			throw "checked callable differs from its declaration";
		final arguments = signature.getArgs();
		final source = declaration.getSourceDeclaration();
		final sourceArguments = source == null ? [] : HxFunctionDecl.getArgs(source);
		final parameters:Array<TyFunctionParameter> = [
			for (index in 0...arguments.length) {
				final parameter = argumentParameter(signature, index);
				{
					name: parameter.name,
					type: parameter.type,
					isOptional: parameter.isOptional,
					isRest: parameter.isRest,
					metadata: index < sourceArguments.length ? HxFunctionArg.getMetadata(sourceArguments[index]) : []
				};
			}
		];
		return new TyCallableSignature(TyType.functionSignature(parameters, signature.getReturnType()), declaration);
	}

	/**
		Read a positional operand's parameter for method ranking and generic inference.
		Trailing rest operands all use the element type; the method body still sees
		its array container. Optional skipping and spread alignment remain the call
		alignment owner's responsibility. No argument rewriting occurs here.
	 */
	public static function argumentParameter(signature:TyFunSig, sourceIndex:Int):Null<TyFunctionParameter> {
		final arguments = signature.getArgs();
		final rest = signature.getArgRest();
		if (sourceIndex < 0 || arguments.length == 0)
			return null;
		final last = arguments.length - 1;
		final index = sourceIndex <= last ? sourceIndex : last < rest.length && rest[last] ? last : -1;
		if (index < 0)
			return null;
		final names = signature.getArgNames();
		final optional = signature.getArgOptional();
		final isRest = index < rest.length && rest[index];
		return {
			name: index < names.length ? names[index] : null,
			type: isRest ? restElement(arguments[index]) : arguments[index],
			isOptional: !isRest && index < optional.length && optional[index],
			isRest: isRest,
			metadata: []
		};
	}

	/** Written ellipsis uses Array in bodies; resolved standard Rest keeps its own container. Callers supply elements. */
	static function restElement(container:TyType):TyType {
		final identity = container.getNominalIdentity();
		final name = identity == null ? container.getUnresolvedPath() : identity.getCanonicalName();
		final arguments = container.getTypeArguments();
		if ((name != "Array" && name != "haxe.Array" && name != "haxe.Rest") || arguments.length != 1)
			throw "rest method signature requires a standard container with one element type";
		return arguments[0];
	}

	public function getDeclaration():Null<TyDeclarationInfo>
		return declaration;

	public function getFunctionType():TyType
		return functionType;

	public function getParameters():Array<TyFunctionParameter>
		return functionType.getFunctionParameters();

	public function getResultType():TyType
		return functionType.getFunctionReturn();

	/** Method-owned generic binders only; enclosing type parameters remain in the type graph. */
	public function getMethodTypeParameters():Array<TyTypeParameterId>
		return methodTypeParameters.copy();
}
