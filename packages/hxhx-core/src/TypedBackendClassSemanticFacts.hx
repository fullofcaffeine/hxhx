/** Semantic declaration kind, before any target erases an abstract to its backing type. */
enum TypedBackendNominalKind {
	ClassInstance;
	EnumValue;
	AbstractValue(underlyingType:TyType);
}

typedef TypedBackendClassFieldFact = {
	final canonicalIdentity:String;
	final constantIdentity:String;
	final name:String;
	final semanticType:TyType;
	final typeIdentity:String;
	final typeDisplay:String;
	final isStatic:Bool;
	final isPublic:Bool;
	final isFinal:Bool;
	final isInline:Bool;
	final hasInitializer:Bool;
	final propertyGet:String;
	final propertySet:String;
	final noImportGlobal:Bool;
};

typedef TypedBackendClassMethodArgumentFact = {
	final name:String;
	final semanticType:TyType;
	final typeIdentity:String;
	final typeDisplay:String;
	final isOptional:Bool;
	final isRest:Bool;
};

typedef TypedBackendClassMethodFact = {
	final canonicalIdentity:String;
	final name:String;
	final isStatic:Bool;
	final typeParameters:Array<TyTypeParameterId>;
	final arguments:Array<TypedBackendClassMethodArgumentFact>;
	final returnSemanticType:TyType;
	final returnTypeIdentity:String;
	final returnTypeDisplay:String;
	final isPublic:Bool;
	final isInline:Bool;
	final isDynamic:Bool;
	final hasBody:Bool;
	final isEnumConstructor:Bool;
	final noImportGlobal:Bool;
};

/**
	Immutable target-neutral class and declared-member facts for one typed class.

	Typing supplies the canonical type, field, method, and superclass identities.
	A backend can later choose target spellings from this record without walking
	a source-shaped class declaration and repeating Haxe name resolution.

	This record contains only members declared by the class. A target that needs
	inherited members must traverse an exact program-owned superclass graph; it
	must not search classes by short name.

	Typed functions contribute finalized body results for unannotated methods.
	Declaration-only consumers pass an empty function list and retain indexed
	signatures. Neither path changes the declaration identities used by calls.
**/
class TypedBackendClassSemanticFacts {
	final classIdentity:String;
	final nominalKind:TypedBackendNominalKind;
	final moduleIdentity:String;
	final typeParameters:Array<TyTypeParameterId>;
	final superType:Null<TyType>;
	final superClassIdentity:Null<String>;
	final superTypeIdentity:Null<String>;
	final superTypeDisplay:Null<String>;
	final isInterface:Bool;
	final isExtern:Bool;
	final interfaceTypes:Array<TyType>;
	final fields:Array<TypedBackendClassFieldFact>;
	final methods:Array<TypedBackendClassMethodFact>;
	final fieldIndex:haxe.ds.StringMap<TypedBackendClassFieldFact>;
	final methodIndex:haxe.ds.StringMap<TypedBackendClassMethodFact>;
	final canonicalIdentity:String;

	public function new(info:TyNominalInfo, resolvedSuperType:Null<TyType>, typedFunctions:Array<TypedFunction>, ?resolvedInterfaces:Array<TyType>) {
		if (info == null)
			throw "typed backend class semantic facts require exact nominal information";
		classIdentity = normalize(info.getIdentity().getCanonicalName());
		moduleIdentity = normalize(info.getModulePath());
		// Only class declarations own interface relationships. This checked boundary
		// keeps enum and abstract facts out of the class/interface membership graph.
		final classInfo:Null<TyClassInfo> = Std.isOfType(info, TyClassInfo) ? cast info : null;
		isInterface = classInfo != null && classInfo.getIsInterface();
		isExtern = classInfo != null && classInfo.getIsExtern();
		final indexedInterfaces = classInfo == null ? [] : classInfo.getInterfaceTypes();
		interfaceTypes = resolvedInterfaces == null ? indexedInterfaces : resolvedInterfaces.copy();
		if (indexedInterfaces.length != interfaceTypes.length)
			throw "typed backend interface parent count changed for " + classIdentity;
		for (index in 0...indexedInterfaces.length)
			if (!hasUnresolvedHeaderType(indexedInterfaces[index])
				&& indexedInterfaces[index].getSemanticKey() != interfaceTypes[index].getSemanticKey())
				throw "typed backend interface parent conflicts with indexed identity for " + classIdentity;
		// This checked semantic-class boundary preserves the typed abstract carrier;
		// targets must not recover abstract identity from its erased display name.
		nominalKind = if (Std.isOfType(info, TyAbstractInfo)) {
			final underlying = (cast info : TyAbstractInfo).getUnderlyingType();
			if (underlying == null)
				throw "typed backend abstract facts require an underlying type for " + classIdentity;
			AbstractValue(underlying);
		} else if (info.getIsEnum()) {
			EnumValue;
		} else {
			ClassInstance;
		};
		typeParameters = if (Std.isOfType(info, TyClassInfo)) {
			(cast info : TyClassInfo).getTypeParameterIds();
		} else if (Std.isOfType(info, TyAbstractInfo)) {
			(cast info : TyAbstractInfo).getTypeParameterIds();
		} else {
			[];
		};
		if (classIdentity.length == 0 || moduleIdentity.length == 0)
			throw "typed backend class semantic facts require canonical class and module identities";
		final seenTypeParameters = new haxe.ds.StringMap<Bool>();
		for (parameter in typeParameters) {
			final parameterName = parameter.getName();
			if (parameterName.length == 0 || seenTypeParameters.exists(parameterName))
				throw "typed backend class semantic facts contain invalid type parameters for " + classIdentity;
			seenTypeParameters.set(parameterName, true);
		}
		switch (nominalKind) {
			case AbstractValue(underlying):
				requireDeclaredTypeParameters(underlying, typeParameters, "abstract " + classIdentity);
			case ClassInstance, EnumValue:
		}

		final indexedSuperType = Std.isOfType(info, TyClassInfo) ? (cast info : TyClassInfo).getSuperType() : null;
		final selectedSuperType = resolvedSuperType == null ? indexedSuperType : resolvedSuperType;
		if (resolvedSuperType != null
			&& indexedSuperType != null
			&& resolvedSuperType.getSemanticKey() != indexedSuperType.getSemanticKey())
			throw "typed backend class semantic facts contain conflicting superclass identities for "
				+ classIdentity
				+ ": indexed "
				+ indexedSuperType.getSemanticKey()
				+ " versus resolved "
				+ resolvedSuperType.getSemanticKey();
		superType = selectedSuperType;
		final superNominalIdentity = selectedSuperType == null ? null : selectedSuperType.getNominalIdentity();
		superClassIdentity = superNominalIdentity == null ? null : normalize(superNominalIdentity.getCanonicalName());
		superTypeIdentity = selectedSuperType == null ? null : selectedSuperType.getSemanticKey();
		superTypeDisplay = selectedSuperType == null ? null : selectedSuperType.getCanonicalDisplay();
		if (selectedSuperType != null)
			requireDeclaredTypeParameters(selectedSuperType, typeParameters, "superclass " + classIdentity);
		for (interfaceType in interfaceTypes)
			requireDeclaredTypeParameters(interfaceType, typeParameters, "interface parent " + classIdentity);

		fieldIndex = new haxe.ds.StringMap<TypedBackendClassFieldFact>();
		for (field in info.getFieldInfos()) {
			if (field == null)
				throw "typed backend class semantic facts contain a null field for " + classIdentity;
			if (field.getOwner().getCanonicalName() != classIdentity || field.getModulePath() != moduleIdentity)
				throw "typed backend class semantic facts contain foreign field " + field.getCanonicalKey() + " in " + classIdentity;
			final fact:TypedBackendClassFieldFact = {
				canonicalIdentity: normalize(field.getCanonicalKey()),
				constantIdentity: field.getConstant().getCanonicalIdentity(),
				name: normalize(field.getName()),
				semanticType: field.getType(),
				typeIdentity: field.getType().getSemanticKey(),
				typeDisplay: field.getType().getCanonicalDisplay(),
				isStatic: field.getIsStatic(),
				isPublic: field.getIsPublic(),
				isFinal: field.getIsFinal(),
				isInline: field.getIsInline(),
				hasInitializer: field.getHasInitializer(),
				propertyGet: field.getPropertyGet(),
				propertySet: field.getPropertySet(),
				noImportGlobal: field.getNoImportGlobal()
			};
			if (fact.typeIdentity.length == 0 || fact.typeDisplay.length == 0)
				throw "typed backend class semantic facts contain an incomplete field type " + fact.canonicalIdentity;
			requireDeclaredTypeParameters(fact.semanticType, typeParameters, "field " + fact.canonicalIdentity);
			addField(fact);
		}

		final bodyResults = new haxe.ds.StringMap<TyType>();
		final seenFunctions = new haxe.ds.StringMap<Bool>();
		for (typedFunction in typedFunctions) {
			final declaration = typedFunction.getDeclaration();
			final environment = typedFunction.getEnvironment();
			if (declaration == null
				|| environment == null
				|| info.declarationForSource(typedFunction.getSourceDeclaration()) != declaration
				|| environment.getOwnerIdentity() != typedFunction.getStableIdentity())
				throw "typed backend class semantic facts contain foreign function result in " + classIdentity;
			final key = declaration.getIdentity().getCanonicalKey();
			if (seenFunctions.exists(key))
				throw "typed backend class semantic facts contain duplicate function result " + key;
			seenFunctions.set(key, true);
			typedFunction.assertParsedBodyCurrent();
			// Bodyless declarations have no inferred completion. Their written
			// signature remains authoritative even if bring-up typing made an environment.
			if (declaration.getHasBody())
				bodyResults.set(key, environment.getReturnType());
		}

		methodIndex = new haxe.ds.StringMap<TypedBackendClassMethodFact>();
		for (declaration in info.getDeclarations()) {
			if (declaration == null)
				throw "typed backend class semantic facts contain a null method for " + classIdentity;
			if (declaration.getOwner().getCanonicalName() != classIdentity || declaration.getModulePath() != moduleIdentity)
				throw "typed backend class semantic facts contain foreign method "
					+ declaration.getIdentity().getCanonicalKey()
					+ " in "
					+ classIdentity;
			final signature = declaration.getSignature();
			final argumentNames = signature.getArgNames();
			final argumentTypes = signature.getArgs();
			final optionalArguments = signature.getArgOptional();
			final restArguments = signature.getArgRest();
			if (argumentNames.length != argumentTypes.length
				|| argumentNames.length != optionalArguments.length
				|| argumentNames.length != restArguments.length)
				throw "typed backend class semantic facts contain an incomplete method signature " + declaration.getIdentity().getCanonicalKey();
			final arguments = new Array<TypedBackendClassMethodArgumentFact>();
			for (index in 0...argumentNames.length) {
				final argument:TypedBackendClassMethodArgumentFact = {
					name: normalize(argumentNames[index]),
					semanticType: argumentTypes[index],
					typeIdentity: argumentTypes[index].getSemanticKey(),
					typeDisplay: argumentTypes[index].getCanonicalDisplay(),
					isOptional: optionalArguments[index],
					isRest: restArguments[index]
				};
				if (argument.name.length == 0 || argument.typeIdentity.length == 0 || argument.typeDisplay.length == 0)
					throw "typed backend class semantic facts contain an incomplete method argument " + declaration.getIdentity().getCanonicalKey();
				arguments.push(argument);
			}
			final returnType = resolvedMethodResult(declaration, bodyResults.get(declaration.getIdentity().getCanonicalKey()));
			final methodTypeParameters = declaration.getTypeParameterIds();
			final seenMethodTypeParameters = new haxe.ds.StringMap<Bool>();
			for (parameter in methodTypeParameters) {
				final parameterName = parameter.getName();
				if (parameterName.length == 0 || seenMethodTypeParameters.exists(parameterName))
					throw "typed backend class semantic facts contain invalid method type parameters for " + declaration.getIdentity().getCanonicalKey();
				seenMethodTypeParameters.set(parameterName, true);
			}
			final allowedTypeParameters = typeParameters.concat(methodTypeParameters);
			final fact:TypedBackendClassMethodFact = {
				canonicalIdentity: normalize(declaration.getIdentity().getCanonicalKey()),
				name: normalize(signature.getName()),
				isStatic: signature.getIsStatic(),
				typeParameters: methodTypeParameters,
				arguments: arguments,
				returnSemanticType: returnType,
				returnTypeIdentity: returnType.getSemanticKey(),
				returnTypeDisplay: returnType.getCanonicalDisplay(),
				isPublic: declaration.getIsPublic(),
				isInline: declaration.getIsInline(),
				isDynamic: declaration.getIsDynamic(),
				hasBody: declaration.getHasBody(),
				isEnumConstructor: declaration.getIsEnumConstructor(),
				noImportGlobal: declaration.getNoImportGlobal()
			};
			if (fact.returnTypeIdentity.length == 0 || fact.returnTypeDisplay.length == 0)
				throw "typed backend class semantic facts contain an incomplete method return type " + fact.canonicalIdentity;
			for (argument in fact.arguments)
				requireDeclaredTypeParameters(argument.semanticType, allowedTypeParameters, "method argument " + fact.canonicalIdentity + "." + argument.name);
			requireDeclaredTypeParameters(fact.returnSemanticType, allowedTypeParameters, "method result " + fact.canonicalIdentity);
			addMethod(fact);
		}

		final fieldIdentities = [for (identity in fieldIndex.keys()) identity];
		fieldIdentities.sort((left, right) -> Reflect.compare(left, right));
		fields = [for (identity in fieldIdentities) copyField(fieldIndex.get(identity))];
		final methodIdentities = [for (identity in methodIndex.keys()) identity];
		methodIdentities.sort((left, right) -> Reflect.compare(left, right));
		methods = [for (identity in methodIdentities) copyMethod(methodIndex.get(identity))];

		final identityFacts = new Array<Null<String>>();
		identityFacts.push(getSchemaRevision());
		identityFacts.push(classIdentity);
		identityFacts.push(moduleIdentity);
		switch (nominalKind) {
			case ClassInstance:
				identityFacts.push("class-instance");
			case EnumValue:
				identityFacts.push("enum-value");
			case AbstractValue(underlying):
				identityFacts.push("abstract-value");
				identityFacts.push(underlying.getSemanticKey());
		}
		identityFacts.push(Std.string(typeParameters.length));
		for (parameter in typeParameters) {
			identityFacts.push(parameter.getCanonicalKey());
			identityFacts.push(parameter.getName());
		}
		identityFacts.push(superClassIdentity);
		identityFacts.push(superTypeIdentity);
		identityFacts.push(superTypeDisplay);
		identityFacts.push(isInterface ? "interface" : "non-interface");
		identityFacts.push(isExtern ? "extern" : "generated");
		identityFacts.push(Std.string(interfaceTypes.length));
		for (interfaceType in interfaceTypes) {
			identityFacts.push(interfaceType.getSemanticKey());
			identityFacts.push(interfaceType.getCanonicalDisplay());
		}
		identityFacts.push("fields");
		identityFacts.push(Std.string(fields.length));
		for (field in fields) {
			identityFacts.push(field.canonicalIdentity);
			identityFacts.push(field.constantIdentity);
			identityFacts.push(field.name);
			identityFacts.push(field.typeIdentity);
			identityFacts.push(field.typeDisplay);
			identityFacts.push(boolText(field.isStatic));
			identityFacts.push(boolText(field.isPublic));
			identityFacts.push(boolText(field.isFinal));
			identityFacts.push(boolText(field.isInline));
			identityFacts.push(boolText(field.hasInitializer));
			identityFacts.push(field.propertyGet);
			identityFacts.push(field.propertySet);
			identityFacts.push(boolText(field.noImportGlobal));
		}
		identityFacts.push("methods");
		identityFacts.push(Std.string(methods.length));
		for (method in methods) {
			identityFacts.push(method.canonicalIdentity);
			identityFacts.push(method.name);
			identityFacts.push(boolText(method.isStatic));
			identityFacts.push(Std.string(method.typeParameters.length));
			for (parameter in method.typeParameters) {
				identityFacts.push(parameter.getCanonicalKey());
				identityFacts.push(parameter.getName());
			}
			identityFacts.push(method.returnTypeIdentity);
			identityFacts.push(method.returnTypeDisplay);
			identityFacts.push(boolText(method.isPublic));
			identityFacts.push(boolText(method.isInline));
			identityFacts.push(boolText(method.isDynamic));
			identityFacts.push(boolText(method.hasBody));
			identityFacts.push(boolText(method.isEnumConstructor));
			identityFacts.push(boolText(method.noImportGlobal));
			identityFacts.push(Std.string(method.arguments.length));
			for (argument in method.arguments) {
				identityFacts.push(argument.name);
				identityFacts.push(argument.typeIdentity);
				identityFacts.push(argument.typeDisplay);
				identityFacts.push(boolText(argument.isOptional));
				identityFacts.push(boolText(argument.isRest));
			}
		}
		canonicalIdentity = CompilerCacheIdentity.encode(identityFacts);
	}

	public function getClassIdentity():String
		return classIdentity;

	/** Returns the semantic receiver kind and, for an abstract, its exact backing type. */
	public function getNominalKind():TypedBackendNominalKind
		return nominalKind;

	public function getModuleIdentity():String
		return moduleIdentity;

	/** Return class-level generic parameters in declared order. **/
	public function getTypeParameters():Array<String>
		return [for (parameter in typeParameters) parameter.getName()];

	/** Return exact class-level generic binder identities in declared order. **/
	public function getTypeParameterIds():Array<TyTypeParameterId>
		return typeParameters.copy();

	/**
		Return the raw nominal node selected as this class's superclass.

		The applied superclass type remains available separately. For example,
		`Base<String>` has the raw graph node `Base` and an applied type that
		retains the `String` argument.
	**/
	public function getSuperClassIdentity():Null<String>
		return superClassIdentity;

	/** Return the immutable structural superclass type selected by typing. **/
	public function getSuperType():Null<TyType>
		return superType;

	/** Extern status belongs to the selected declaration and affects target generation. */
	public function getIsExtern():Bool
		return isExtern;

	public function getIsInterface():Bool
		return isInterface;

	/** Exact implemented or extended interface types, without constructor meaning. */
	public function getInterfaceTypes():Array<TyType>
		return interfaceTypes.copy();

	/** Early index observations can retain names whose provider has not loaded yet. */
	static function hasUnresolvedHeaderType(type:TyType):Bool {
		if (type.isUnknown() || type.isUnresolved())
			return true;
		for (argument in type.getTypeArguments())
			if (hasUnresolvedHeaderType(argument))
				return true;
		return false;
	}

	public function getSuperTypeIdentity():Null<String>
		return superTypeIdentity;

	public function getSuperTypeDisplay():Null<String>
		return superTypeDisplay;

	public function getSchemaRevision():String
		return "typed-backend-class-semantic-facts-v9";

	/**
		Publish an inferred result without replacing the declaration key selected
		before body typing. Written results remain contracts. Constructors describe
		the allocated value in their signature and complete with Void in their body.
	**/
	static function resolvedMethodResult(declaration:TyDeclarationInfo, bodyResult:Null<TyType>):TyType {
		final signature = declaration.getSignature();
		final declaredResult = signature.getReturnType();
		if (bodyResult == null)
			return declaredResult;
		if (signature.getName() == "new" && !signature.getIsStatic()) {
			if (bodyResult.getSemanticKey() != TyType.fromHintText("Void").getSemanticKey())
				throw "typed backend constructor body must complete with Void: " + declaration.getIdentity().getCanonicalKey();
			return declaredResult;
		}
		if (!declaredResult.isUnknown() && declaredResult.getSemanticKey() != bodyResult.getSemanticKey())
			throw "typed backend class semantic facts contain conflicting function result " + declaration.getIdentity().getCanonicalKey();
		return bodyResult;
	}

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function copyFields():Array<TypedBackendClassFieldFact>
		return [for (field in fields) copyField(field)];

	public function copyMethods():Array<TypedBackendClassMethodFact>
		return [for (method in methods) copyMethod(method)];

	public function findField(canonicalFieldIdentity:String):Null<TypedBackendClassFieldFact> {
		final fact = fieldIndex.get(canonicalFieldIdentity);
		return fact == null ? null : copyField(fact);
	}

	public function findMethod(canonicalDeclarationIdentity:String):Null<TypedBackendClassMethodFact> {
		final fact = methodIndex.get(canonicalDeclarationIdentity);
		return fact == null ? null : copyMethod(fact);
	}

	function addField(fact:TypedBackendClassFieldFact):Void {
		if (fact.canonicalIdentity.length == 0 || fact.name.length == 0)
			throw "typed backend class semantic facts contain an incomplete field for " + classIdentity;
		final previous = fieldIndex.get(fact.canonicalIdentity);
		if (previous == null)
			fieldIndex.set(fact.canonicalIdentity, copyField(fact));
		else if (!sameField(previous, fact))
			throw "typed backend class semantic facts contain conflicting field " + fact.canonicalIdentity;
	}

	function addMethod(fact:TypedBackendClassMethodFact):Void {
		if (fact.canonicalIdentity.length == 0 || fact.name.length == 0)
			throw "typed backend class semantic facts contain an incomplete method for " + classIdentity;
		final previous = methodIndex.get(fact.canonicalIdentity);
		if (previous == null)
			methodIndex.set(fact.canonicalIdentity, copyMethod(fact));
		else if (!sameMethod(previous, fact))
			throw "typed backend class semantic facts contain conflicting method " + fact.canonicalIdentity;
	}

	static function sameField(left:TypedBackendClassFieldFact, right:TypedBackendClassFieldFact):Bool
		return left.canonicalIdentity == right.canonicalIdentity
			&& left.name == right.name
			&& left.semanticType.getSemanticKey() == right.semanticType.getSemanticKey()
			&& left.typeIdentity == right.typeIdentity
			&& left.constantIdentity == right.constantIdentity
			&& left.typeDisplay == right.typeDisplay
			&& left.isStatic == right.isStatic
			&& left.isPublic == right.isPublic
			&& left.isFinal == right.isFinal
			&& left.isInline == right.isInline
			&& left.hasInitializer == right.hasInitializer
			&& left.propertyGet == right.propertyGet
			&& left.propertySet == right.propertySet
			&& left.noImportGlobal == right.noImportGlobal;

	static function sameMethod(left:TypedBackendClassMethodFact, right:TypedBackendClassMethodFact):Bool {
		if (left.canonicalIdentity != right.canonicalIdentity
			|| left.name != right.name
			|| left.isStatic != right.isStatic
			|| !sameTypeParameters(left.typeParameters, right.typeParameters)
			|| left.returnSemanticType.getSemanticKey() != right.returnSemanticType.getSemanticKey()
			|| left.returnTypeIdentity != right.returnTypeIdentity
			|| left.returnTypeDisplay != right.returnTypeDisplay
			|| left.isPublic != right.isPublic
			|| left.isInline != right.isInline
			|| left.isDynamic != right.isDynamic
			|| left.hasBody != right.hasBody
			|| left.isEnumConstructor != right.isEnumConstructor
			|| left.noImportGlobal != right.noImportGlobal
			|| left.arguments.length != right.arguments.length)
			return false;
		for (index in 0...left.arguments.length) {
			final leftArgument = left.arguments[index];
			final rightArgument = right.arguments[index];
			if (leftArgument.name != rightArgument.name
				|| leftArgument.semanticType.getSemanticKey() != rightArgument.semanticType.getSemanticKey()
				|| leftArgument.typeIdentity != rightArgument.typeIdentity
				|| leftArgument.typeDisplay != rightArgument.typeDisplay
				|| leftArgument.isOptional != rightArgument.isOptional
				|| leftArgument.isRest != rightArgument.isRest)
				return false;
		}
		return true;
	}

	static function copyField(fact:TypedBackendClassFieldFact):TypedBackendClassFieldFact
		return {
			canonicalIdentity: fact.canonicalIdentity,
			constantIdentity: fact.constantIdentity,
			name: fact.name,
			semanticType: fact.semanticType,
			typeIdentity: fact.typeIdentity,
			typeDisplay: fact.typeDisplay,
			isStatic: fact.isStatic,
			isPublic: fact.isPublic,
			isFinal: fact.isFinal,
			isInline: fact.isInline,
			hasInitializer: fact.hasInitializer,
			propertyGet: fact.propertyGet,
			propertySet: fact.propertySet,
			noImportGlobal: fact.noImportGlobal
		};

	static function copyArgument(fact:TypedBackendClassMethodArgumentFact):TypedBackendClassMethodArgumentFact
		return {
			name: fact.name,
			semanticType: fact.semanticType,
			typeIdentity: fact.typeIdentity,
			typeDisplay: fact.typeDisplay,
			isOptional: fact.isOptional,
			isRest: fact.isRest
		};

	static function copyMethod(fact:TypedBackendClassMethodFact):TypedBackendClassMethodFact
		return {
			canonicalIdentity: fact.canonicalIdentity,
			name: fact.name,
			isStatic: fact.isStatic,
			typeParameters: fact.typeParameters.copy(),
			arguments: [for (argument in fact.arguments) copyArgument(argument)],
			returnSemanticType: fact.returnSemanticType,
			returnTypeIdentity: fact.returnTypeIdentity,
			returnTypeDisplay: fact.returnTypeDisplay,
			isPublic: fact.isPublic,
			isInline: fact.isInline,
			isDynamic: fact.isDynamic,
			hasBody: fact.hasBody,
			isEnumConstructor: fact.isEnumConstructor,
			noImportGlobal: fact.noImportGlobal
		};

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);

	static function boolText(value:Bool):String
		return value ? "true" : "false";

	static function requireDeclaredTypeParameters(type:TyType, allowed:Array<TyTypeParameterId>, context:String):Void {
		final allowedKeys = new haxe.ds.StringMap<Bool>();
		for (parameter in allowed)
			allowedKeys.set(parameter.getCanonicalKey(), true);
		for (parameter in TyTypeSubstitution.parameterIdentities(type))
			if (!allowedKeys.exists(parameter.getCanonicalKey()))
				throw "typed backend class semantic facts contain unbound type parameter " + parameter.getName() + " in " + context;
	}

	static function sameTypeParameters(left:Array<TyTypeParameterId>, right:Array<TyTypeParameterId>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length)
			if (!left[index].equals(right[index]))
				return false;
		return true;
	}
}
