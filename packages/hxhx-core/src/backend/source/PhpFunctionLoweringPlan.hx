package backend.source;

import TypedBackendClassGraph.TypedBackendClassTypeBinding;
import TypedBackendClassGraph.TypedBackendSpecializedClassNode;
import TypedBackendClassSemanticFacts.TypedBackendClassFieldFact;
import TypedBackendClassSemanticFacts.TypedBackendClassMethodArgumentFact;
import TypedBackendClassSemanticFacts.TypedBackendClassMethodFact;
import TyLocalDeclarationKind.TyLocalDeclarationKindTools;
import backend.source.PhpFunctionLocalFacts.PhpFunctionLocalFact;

typedef PhpFunctionPlanLocalFact = {
	final projectedName:String;
	final targetName:String;
	final bindingIdentity:String;
	final sourceName:String;
	final semanticType:TyType;
	final typeIdentity:String;
	final typeDisplay:String;
	final declarationKind:TyLocalDeclarationKind;
	final isRestCarrier:Bool;
	final targetTypeHint:String;
};

typedef PhpFunctionPlanFieldReadFact = {
	final projectedName:String;
	final targetName:String;
	final canonicalIdentity:String;
	final ownerIdentity:String;
	final moduleIdentity:String;
	final name:String;
	final semanticType:TyType;
	final typeIdentity:String;
	final typeDisplay:String;
	final isStatic:Bool;
	final isPublic:Bool;
	final isFinal:Bool;
	final isInline:Bool;
	final hasInitializer:Bool;
	final noImportGlobal:Bool;
};

typedef PhpFunctionPlanEnumConstructorFact = {
	final ownerIdentity:String;
	final moduleIdentity:String;
	final declarationIdentity:String;
	final enumName:String;
	final constructorName:String;
	final hasArguments:Bool;
};

private typedef PhpFunctionPlanEnumConstructorCatalog = {
	final byName:haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>;
	final ambiguousNames:haxe.ds.StringMap<Bool>;
	final localByName:haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>;
	final localAmbiguousNames:haxe.ds.StringMap<Bool>;
	final byOwner:haxe.ds.StringMap<haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>>;
	final byDeclaration:haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>;
	final ownerByEmittedName:haxe.ds.StringMap<String>;
};

/**
	Sealed PHP input for rendering one exact typed executable unit.

	An executable unit is either an ordinary function body or one typed field
	initializer. The plan joins target-neutral program, module, class, unit,
	local, field, and specialized inheritance facts before recursive syntax
	rendering starts.
	It deliberately preserves inherited classes as child-to-root groups instead
	of flattening members by readable name. A later renderer must select members
	by their exact declaration identity and cannot silently choose an override
	or a same-short-name class by traversal order.

	`PhpFunctionBodyRenderer` consumes this record in production for ordinary,
	support, constructor, accessor, initializer, and selected-main executable
	units. Its canonical identity is process-local evidence, not a persistent
	cache key.
**/
class PhpFunctionLoweringPlan {
	final programRevision:String;
	final moduleRevision:String;
	final moduleIdentity:String;
	final classIdentity:String;
	final classFactsIdentity:String;
	final functionIdentity:String;
	final bodyRevision:String;
	final emittedClassName:String;
	final classUsesThisValueSlot:Bool;
	final currentMethod:Null<TypedBackendClassMethodFact>;
	final currentField:Null<TypedBackendClassFieldFact>;
	final classGraph:TypedBackendClassGraph;
	final specializedLineage:Array<TypedBackendSpecializedClassNode>;
	final parameterBindingIdentities:Array<String>;
	final locals:Array<PhpFunctionPlanLocalFact>;
	final localIndex:haxe.ds.StringMap<PhpFunctionPlanLocalFact>;
	final instanceFieldTypeHints:haxe.ds.StringMap<String>;
	final stringExtensionOwners:haxe.ds.StringMap<String>;
	final fieldReads:Array<PhpFunctionPlanFieldReadFact>;
	final enumConstructors:PhpFunctionPlanEnumConstructorCatalog;
	final canonicalIdentity:String;

	public function new(programFacts:PhpProgramRenderFacts, moduleFacts:PhpModuleRenderFacts, classGraph:TypedBackendClassGraph,
			classFacts:TypedBackendClassSemanticFacts, classUsesThisValueSlot:Bool, ?functionProjection:TypedBackendFunctionProjection,
			?fieldInitializerProjection:TypedBackendFieldInitializerProjection) {
		if (programFacts == null || moduleFacts == null || classGraph == null || classFacts == null)
			throw "PHP function lowering plan requires complete typed facts";
		if ((functionProjection == null) == (fieldInitializerProjection == null))
			throw "PHP function lowering plan requires exactly one function or field initializer";

		programRevision = normalize(programFacts.getProgramRevision());
		moduleRevision = normalize(moduleFacts.getModuleRevision());
		moduleIdentity = normalize(moduleFacts.getModuleIdentity());
		classIdentity = normalize(classFacts.getClassIdentity());
		classFactsIdentity = normalize(classFacts.getCanonicalIdentity());
		final initializerMode = fieldInitializerProjection != null;
		functionIdentity = normalize(initializerMode ? fieldInitializerProjection.getStableIdentity() : functionProjection.getStableIdentity());
		bodyRevision = normalize(initializerMode ? fieldInitializerProjection.getBodyRevision() : functionProjection.getBodyRevision());
		if (programRevision.length == 0 || moduleRevision.length == 0 || moduleIdentity.length == 0 || classIdentity.length == 0
			|| classFactsIdentity.length == 0 || functionIdentity.length == 0 || bodyRevision.length == 0)
			throw "PHP function lowering plan contains an incomplete revision or semantic identity";
		if (moduleFacts.getProgramRevision() != programRevision || classGraph.getProgramRevision() != programRevision)
			throw "PHP function lowering plan received mismatched typed-program revisions for " + functionIdentity;
		if (classFacts.getModuleIdentity() != moduleIdentity)
			throw "PHP function lowering plan received class " + classIdentity + " from module " + classFacts.getModuleIdentity() + " while planning "
				+ moduleIdentity;
		final graphFacts = classGraph.findClassFacts(classIdentity);
		if (graphFacts == null || graphFacts.getCanonicalIdentity() != classFactsIdentity)
			throw "PHP function lowering plan received stale class facts for " + classIdentity;

		if (initializerMode) {
			final initializerField = fieldInitializerProjection.getField();
			var selectedField:Null<TypedBackendClassFieldFact> = null;
			for (field in classFacts.copyFields())
				if (field.canonicalIdentity == initializerField.getCanonicalKey()) {
					selectedField = field;
					break;
				}
			if (selectedField == null)
				throw "PHP function lowering plan cannot find exact field initializer " + functionIdentity + " in " + classIdentity;
			currentField = copyField(selectedField);
			currentMethod = null;
		} else {
			final selectedMethod = classFacts.findMethod(functionIdentity);
			if (selectedMethod == null)
				throw "PHP function lowering plan cannot find exact method " + functionIdentity + " in " + classIdentity;
			currentMethod = copyMethod(selectedMethod);
			currentField = null;
		}
		emittedClassName = normalize(programFacts.findEmittedTypeName(classIdentity));
		if (emittedClassName.length == 0)
			throw "PHP function lowering plan cannot find emitted class " + classIdentity;
		this.classUsesThisValueSlot = classUsesThisValueSlot;

		this.classGraph = classGraph;
		specializedLineage = classGraph.requireSpecializedLineage(classIdentity);
		if (specializedLineage.length == 0
			|| specializedLineage[0].classIdentity != classIdentity
			|| specializedLineage[0].classFactsIdentity != classFactsIdentity)
			throw "PHP function lowering plan received an incomplete specialized lineage for " + classIdentity;

		parameterBindingIdentities = initializerMode ? [] : functionProjection.getParameterBindingIdentities();
		final methodArguments = currentMethod == null ? [] : currentMethod.arguments;
		if (parameterBindingIdentities.length != methodArguments.length)
			throw "PHP function lowering plan received " + parameterBindingIdentities.length + " exact parameter bindings for " + methodArguments.length
				+ " method arguments in " + functionIdentity;
		final restParameterBindings = new haxe.ds.StringMap<Bool>();
		for (index in 0...methodArguments.length)
			if (methodArguments[index].isRest)
				restParameterBindings.set(parameterBindingIdentities[index], true);
		final observedLocals = (initializerMode ? PhpFunctionLocalFacts.fromCatalog(fieldInitializerProjection.getLocalCatalog(),
			PhpName.valueIdentifier) : new PhpFunctionLocalFacts(functionProjection, PhpName.valueIdentifier)).copyLocals();
		locals = [];
		localIndex = new haxe.ds.StringMap<PhpFunctionPlanLocalFact>();
		for (local in observedLocals) {
			final isRestCarrier = restParameterBindings.exists(local.bindingIdentity);
			final fact:PhpFunctionPlanLocalFact = {
				projectedName: local.projectedName,
				targetName: local.targetName,
				bindingIdentity: local.bindingIdentity,
				sourceName: local.sourceName,
				semanticType: local.semanticType,
				typeIdentity: local.typeIdentity,
				typeDisplay: local.typeDisplay,
				declarationKind: local.declarationKind,
				isRestCarrier: isRestCarrier,
				targetTypeHint: isRestCarrier ? "Array<RestValue>" : semanticTypeHint(local)
			};
			if (localIndex.exists(fact.targetName))
				throw "PHP function lowering plan contains conflicting local target name " + fact.targetName + " in " + functionIdentity;
			localIndex.set(fact.targetName, copyLocal(fact));
			locals.push(copyLocal(fact));
		}
		requireExactParameters(methodArguments, parameterBindingIdentities);

		instanceFieldTypeHints = new haxe.ds.StringMap<String>();
		for (field in classFacts.copyFields())
			if (!field.isStatic)
				instanceFieldTypeHints.set(PhpName.valueIdentifier(field.name), field.typeDisplay);
		stringExtensionOwners = buildStringExtensionOwners(programFacts, moduleFacts, classGraph, specializedLineage, functionIdentity);

		fieldReads = [];
		final seenFieldTargets = new haxe.ds.StringMap<String>();
		final fieldReadCatalog = initializerMode ? fieldInitializerProjection.getFieldReadCatalog() : functionProjection.getFieldReadCatalog();
		for (read in fieldReadCatalog.getEntries()) {
			final field = read.getField();
			final targetName = PhpName.valueIdentifier(read.getProjectedName());
			final fact:PhpFunctionPlanFieldReadFact = {
				projectedName: read.getProjectedName(),
				targetName: targetName,
				canonicalIdentity: field.getCanonicalKey(),
				ownerIdentity: field.getOwner().getCanonicalName(),
				moduleIdentity: field.getModulePath(),
				name: field.getName(),
				semanticType: field.getType(),
				typeIdentity: field.getType().getSemanticKey(),
				typeDisplay: field.getType().getCanonicalDisplay(),
				isStatic: field.getIsStatic(),
				isPublic: field.getIsPublic(),
				isFinal: field.getIsFinal(),
				isInline: field.getIsInline(),
				hasInitializer: field.getHasInitializer(),
				noImportGlobal: field.getNoImportGlobal()
			};
			final previous = seenFieldTargets.get(targetName);
			if (previous != null && previous != fact.canonicalIdentity)
				throw "PHP function lowering plan contains conflicting field reads for target name " + targetName + " in " + functionIdentity;
			seenFieldTargets.set(targetName, fact.canonicalIdentity);
			fieldReads.push(copyFieldRead(fact));
		}
		fieldReads.sort((left, right) -> Reflect.compare(fieldReadSortIdentity(left), fieldReadSortIdentity(right)));
		enumConstructors = buildEnumConstructorCatalog(programFacts, classGraph, moduleIdentity, functionIdentity);

		final identityFacts = new Array<Null<String>>();
		identityFacts.push(getSchemaRevision());
		identityFacts.push(programRevision);
		identityFacts.push(programFacts.getSchemaRevision());
		identityFacts.push(programFacts.getCanonicalIdentity());
		identityFacts.push(moduleRevision);
		identityFacts.push(moduleFacts.getSchemaRevision());
		identityFacts.push(moduleFacts.getCanonicalIdentity());
		identityFacts.push(moduleIdentity);
		identityFacts.push(classIdentity);
		identityFacts.push(classFacts.getSchemaRevision());
		identityFacts.push(classFactsIdentity);
		identityFacts.push(classGraph.getSchemaRevision());
		identityFacts.push(classGraph.getCanonicalIdentity());
		identityFacts.push(functionIdentity);
		identityFacts.push(bodyRevision);
		identityFacts.push(emittedClassName);
		identityFacts.push("class-uses-this-value-slot");
		identityFacts.push(boolText(classUsesThisValueSlot));
		identityFacts.push("parameter-bindings");
		identityFacts.push(Std.string(parameterBindingIdentities.length));
		for (identity in parameterBindingIdentities)
			identityFacts.push(identity);
		if (currentMethod != null) {
			identityFacts.push("function");
			addMethodIdentity(identityFacts, currentMethod);
		} else {
			identityFacts.push("field-initializer");
			addFieldIdentity(identityFacts, currentField);
		}
		identityFacts.push("lineage");
		identityFacts.push(Std.string(specializedLineage.length));
		for (node in specializedLineage)
			addLineageIdentity(identityFacts, node);
		identityFacts.push("locals");
		identityFacts.push(Std.string(locals.length));
		for (local in locals) {
			identityFacts.push(local.projectedName);
			identityFacts.push(local.targetName);
			identityFacts.push(local.bindingIdentity);
			identityFacts.push(local.sourceName);
			identityFacts.push(local.typeIdentity);
			identityFacts.push(local.typeDisplay);
			identityFacts.push(TyLocalDeclarationKindTools.canonicalName(local.declarationKind));
			identityFacts.push(boolText(local.isRestCarrier));
			identityFacts.push(local.targetTypeHint);
		}
		identityFacts.push("field-reads");
		identityFacts.push(Std.string(fieldReads.length));
		for (field in fieldReads) {
			identityFacts.push(field.projectedName);
			identityFacts.push(field.targetName);
			identityFacts.push(field.canonicalIdentity);
			identityFacts.push(field.ownerIdentity);
			identityFacts.push(field.moduleIdentity);
			identityFacts.push(field.name);
			identityFacts.push(field.typeIdentity);
			identityFacts.push(field.typeDisplay);
			identityFacts.push(boolText(field.isStatic));
			identityFacts.push(boolText(field.isPublic));
			identityFacts.push(boolText(field.isFinal));
			identityFacts.push(boolText(field.isInline));
			identityFacts.push(boolText(field.hasInitializer));
			identityFacts.push(boolText(field.noImportGlobal));
		}
		final extensionNames = [for (name in stringExtensionOwners.keys()) name];
		extensionNames.sort((left, right) -> Reflect.compare(left, right));
		identityFacts.push("string-extension-owners");
		identityFacts.push(Std.string(extensionNames.length));
		for (name in extensionNames) {
			identityFacts.push(name);
			identityFacts.push(stringExtensionOwners.get(name));
		}
		final enumDeclarations = [for (declaration in enumConstructors.byDeclaration.keys()) declaration];
		enumDeclarations.sort((left, right) -> Reflect.compare(left, right));
		identityFacts.push("enum-constructors");
		identityFacts.push(Std.string(enumDeclarations.length));
		for (declaration in enumDeclarations)
			addEnumConstructorIdentity(identityFacts, enumConstructors.byDeclaration.get(declaration));
		final ambiguousEnumNames = [for (name in enumConstructors.ambiguousNames.keys()) name];
		ambiguousEnumNames.sort((left, right) -> Reflect.compare(left, right));
		identityFacts.push("ambiguous-enum-constructors");
		identityFacts.push(Std.string(ambiguousEnumNames.length));
		for (name in ambiguousEnumNames)
			identityFacts.push(name);
		final localAmbiguousEnumNames = [for (name in enumConstructors.localAmbiguousNames.keys()) name];
		localAmbiguousEnumNames.sort((left, right) -> Reflect.compare(left, right));
		identityFacts.push("local-ambiguous-enum-constructors");
		identityFacts.push(Std.string(localAmbiguousEnumNames.length));
		for (name in localAmbiguousEnumNames)
			identityFacts.push(name);
		canonicalIdentity = CompilerCacheIdentity.encode(identityFacts);
	}

	public function getSchemaRevision():String
		return "php-function-lowering-plan-v5";

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function getProgramRevision():String
		return programRevision;

	public function getModuleRevision():String
		return moduleRevision;

	public function getModuleIdentity():String
		return moduleIdentity;

	public function getClassIdentity():String
		return classIdentity;

	public function getClassFactsIdentity():String
		return classFactsIdentity;

	public function getFunctionIdentity():String
		return functionIdentity;

	public function getBodyRevision():String
		return bodyRevision;

	public function getEmittedClassName():String
		return emittedClassName;

	/** Report whether every method in the rendered class must use the shared value carrier. **/
	public function usesThisValueSlot():Bool
		return classUsesThisValueSlot;

	public function copyCurrentMethod():TypedBackendClassMethodFact {
		if (currentMethod == null)
			throw "PHP field initializer plan has no current method: " + functionIdentity;
		return copyMethod(currentMethod);
	}

	public function copyCurrentField():TypedBackendClassFieldFact {
		if (currentField == null)
			throw "PHP function plan has no current field: " + functionIdentity;
		return copyField(currentField);
	}

	/** Report whether the active function is one accessor for the named property. **/
	public function isCurrentPropertyAccessor(targetFieldName:String):Bool {
		if (currentMethod == null)
			return false;
		final field = PhpName.valueIdentifier(targetFieldName);
		final method = PhpName.valueIdentifier(currentMethod.name);
		return method == "get_" + field || method == "set_" + field;
	}

	/** Report whether the current class lineage exposes an instance method. **/
	public function hasCurrentInstanceMethod(targetName:String):Bool
		return specializedLineageHasInstanceMethod(specializedLineage, targetName);

	/** Return the exact callable arguments selected from the current class lineage. **/
	public function findCurrentInstanceMethodArguments(targetName:String):Null<Array<HxFunctionArg>>
		return specializedLineageFindInstanceMethodArguments(specializedLineage, targetName);

	/** Report whether the current class lineage exposes an instance field. **/
	public function hasCurrentInstanceField(targetName:String):Bool
		return specializedLineageFindInstanceField(specializedLineage, targetName) != null;

	/**
		Return the exact instance methods visible to the active function.

		Static functions cannot use an unqualified instance member, so their map
		is deliberately empty. Names are returned in PHP target-name space for
		the bounded source-shaped rewrite that runs before syntax rendering.
	**/
	public function copyCurrentInstanceMethodTargetNames():haxe.ds.StringMap<Bool> {
		final out = new haxe.ds.StringMap<Bool>();
		if (!hasCurrentInstanceContext())
			return out;
		for (node in specializedLineage)
			for (method in node.methods)
				if (!method.isStatic)
					out.set(PhpName.valueIdentifier(method.name), true);
		return out;
	}

	/** Return the exact instance fields visible to the active function. **/
	public function copyCurrentInstanceFieldTargetNames():haxe.ds.StringMap<Bool> {
		final out = new haxe.ds.StringMap<Bool>();
		if (!hasCurrentInstanceContext())
			return out;
		for (node in specializedLineage)
			for (field in node.fields)
				if (!field.isStatic)
					out.set(PhpName.valueIdentifier(field.name), true);
		return out;
	}

	/**
		Return static members declared by the active class.

		Inherited static lookup is not guessed here. The existing rewrite only
		qualifies unqualified members declared on the current class; explicit
		parent or foreign-owner calls remain attached to their typed receiver.
	**/
	public function copyCurrentClassStaticMemberTargetNames():haxe.ds.StringMap<Bool> {
		final out = new haxe.ds.StringMap<Bool>();
		final current = specializedLineage[0];
		for (field in current.fields)
			if (field.isStatic)
				out.set(PhpName.valueIdentifier(field.name), true);
		for (method in current.methods)
			if (method.isStatic)
				out.set(PhpName.valueIdentifier(method.name), true);
		return out;
	}

	/** Return exact parameter target names that shadow same-class members. **/
	public function copyParameterTargetNames():Array<String> {
		final out = new Array<String>();
		for (bindingIdentity in parameterBindingIdentities)
			for (local in locals)
				if (local.bindingIdentity == bindingIdentity) {
					out.push(local.targetName);
					break;
				}
		if (out.length != parameterBindingIdentities.length)
			throw "PHP function lowering plan cannot recover every parameter target name in " + functionIdentity;
		return out;
	}

	/**
		Report whether an exact semantic receiver type exposes an instance method.

		Unknown, structural, or external receiver types are not guessed. Callers
		may retain a bounded legacy fallback while the PHP hard cut is staged.
	**/
	public function semanticTypeHasInstanceMethod(type:Null<TyType>, targetName:String):Bool {
		final lineage = semanticTypeLineage(type);
		return lineage == null ? false : specializedLineageHasInstanceMethod(lineage, targetName);
	}

	/** Return exact arguments for one method on an exact semantic receiver type. **/
	public function semanticTypeInstanceMethodArguments(type:Null<TyType>, targetName:String):Null<Array<HxFunctionArg>> {
		final lineage = semanticTypeLineage(type);
		return lineage == null ? null : specializedLineageFindInstanceMethodArguments(lineage, targetName);
	}

	/**
		Report whether an exact semantic receiver inherits a dynamic method.

		A child override remains dynamically replaceable when the declaration
		contract originates on an ancestor, so every lineage node is inspected.
	**/
	public function semanticTypeHasDynamicInstanceMethod(type:Null<TyType>, targetName:String):Bool {
		final lineage = semanticTypeLineage(type);
		return lineage == null ? false : specializedLineageHasDynamicInstanceMethod(lineage, targetName);
	}

	/** Report whether an exact semantic receiver type exposes an instance field. **/
	public function semanticTypeHasInstanceField(type:Null<TyType>, targetName:String):Bool {
		final lineage = semanticTypeLineage(type);
		return lineage == null ? false : specializedLineageFindInstanceField(lineage, targetName) != null;
	}

	/** Report whether an exact generic-specialized receiver field is callable. **/
	public function semanticTypeHasCallableInstanceField(type:Null<TyType>, targetName:String):Bool {
		final lineage = semanticTypeLineage(type);
		if (lineage == null)
			return false;
		final field = specializedLineageFindInstanceField(lineage, targetName);
		return field != null && field.semanticType.isFunction();
	}

	/** Return the exact generic-specialized receiver field type for call alignment. **/
	public function semanticTypeInstanceFieldTypeHint(type:Null<TyType>, targetName:String):Null<String> {
		final lineage = semanticTypeLineage(type);
		if (lineage == null)
			return null;
		final field = specializedLineageFindInstanceField(lineage, targetName);
		return field == null ? null : field.typeDisplay;
	}

	/** Report whether an exact semantic receiver field uses a Haxe getter. **/
	public function semanticTypeUsesPropertyGetter(type:Null<TyType>, targetFieldName:String):Bool {
		final lineage = semanticTypeLineage(type);
		return lineage == null ? false : specializedLineageUsesPropertyAccessor(lineage, targetFieldName, true);
	}

	/** Report whether an exact semantic receiver field uses a Haxe setter. **/
	public function semanticTypeUsesPropertySetter(type:Null<TyType>, targetFieldName:String):Bool {
		final lineage = semanticTypeLineage(type);
		return lineage == null ? false : specializedLineageUsesPropertyAccessor(lineage, targetFieldName, false);
	}

	public function copyParameterBindingIdentities():Array<String>
		return parameterBindingIdentities.copy();

	public function copySpecializedLineage():Array<TypedBackendSpecializedClassNode>
		return [for (node in specializedLineage) copyNode(node)];

	public function copyLocals():Array<PhpFunctionPlanLocalFact>
		return [for (local in locals) copyLocal(local)];

	public function findLocalByTargetName(targetName:String):Null<PhpFunctionPlanLocalFact> {
		final fact = localIndex.get(normalize(targetName));
		return fact == null ? null : copyLocal(fact);
	}

	/**
		Return the exact parameter used as a runtime sample for a generic constructor.

		PHP cannot instantiate a type parameter directly. The established
		lowering constructs another value with the runtime class of a parameter
		whose exact semantic type is that binder.
	**/
	public function findGenericConstructorSampleTargetName(typeParameterName:String):Null<String> {
		if (currentMethod == null || !currentMethod.isStatic)
			return null;
		final expected = normalize(typeParameterName);
		if (expected.length == 0)
			return null;
		for (index in 0...currentMethod.arguments.length) {
			final argument = currentMethod.arguments[index];
			if (!argument.semanticType.isTypeParameter() || argument.semanticType.getTypeParameterName() != expected)
				continue;
			final bindingIdentity = parameterBindingIdentities[index];
			for (local in locals)
				if (local.bindingIdentity == bindingIdentity)
					return local.targetName;
			throw "PHP function lowering plan cannot find generic sample parameter " + bindingIdentity + " in " + functionIdentity;
		}
		return null;
	}

	/** Return the exact declared type of one current-class instance field. **/
	public function findInstanceFieldTypeHint(targetName:String):Null<String> {
		final normalized = PhpName.valueIdentifier(targetName);
		return instanceFieldTypeHints.exists(normalized) ? instanceFieldTypeHints.get(normalized) : null;
	}

	/** Return the exact imported owner selected for one String extension method. **/
	public function findStringExtensionOwner(targetName:String):Null<String>
		return stringExtensionOwners.get(PhpName.valueIdentifier(targetName));

	/**
		Resolve one constructor from exact typed-program facts.

		An exact owner from a typed peer expression wins. Otherwise a constructor
		must be unambiguous in the current module or in the complete program.
	**/
	public function findEnumConstructor(targetName:String, ?preferredOwnerIdentity:String):Null<PhpFunctionPlanEnumConstructorFact> {
		final name = PhpName.valueIdentifier(targetName);
		final preferredOwner = normalize(preferredOwnerIdentity);
		if (preferredOwner.length > 0) {
			final exactOwner = enumConstructors.ownerByEmittedName.exists(preferredOwner) ? enumConstructors.ownerByEmittedName.get(preferredOwner) : preferredOwner;
			final byConstructor = enumConstructors.byOwner.get(exactOwner);
			if (byConstructor != null && byConstructor.exists(name))
				return copyEnumConstructor(byConstructor.get(name));
		}
		if (enumConstructors.localByName.exists(name) && !enumConstructors.localAmbiguousNames.exists(name))
			return copyEnumConstructor(enumConstructors.localByName.get(name));
		if (enumConstructors.ambiguousNames.exists(name))
			return null;
		final fact = enumConstructors.byName.get(name);
		return fact == null ? null : copyEnumConstructor(fact);
	}

	/** Resolve an already-selected typed enum-constructor declaration. **/
	public function requireExactEnumConstructor(ownerIdentity:String, modulePath:String, declarationIdentity:String,
			constructorName:String):PhpFunctionPlanEnumConstructorFact {
		final declaration = normalize(declarationIdentity);
		final fact = enumConstructors.byDeclaration.get(declaration);
		if (fact == null)
			throw "PHP function lowering plan cannot find exact enum constructor " + declaration + " in " + functionIdentity;
		if (fact.ownerIdentity != normalize(ownerIdentity)
			|| fact.moduleIdentity != normalize(modulePath)
			|| fact.constructorName != PhpName.valueIdentifier(constructorName))
			throw "PHP exact enum-constructor marker disagrees with sealed declaration " + declaration;
		return copyEnumConstructor(fact);
	}

	/** Return the exact enum owner carried by a semantic local type. **/
	public function findEnumOwnerIdentity(type:Null<TyType>):Null<String> {
		if (type == null)
			return null;
		final exact = type.isNullable() ? type.unwrapNull() : type;
		final nominal = exact.getNominalIdentity();
		if (nominal == null)
			return null;
		final ownerIdentity = nominal.getCanonicalName();
		return enumConstructors.byOwner.exists(ownerIdentity) ? ownerIdentity : null;
	}

	public function copyFieldReads():Array<PhpFunctionPlanFieldReadFact>
		return [for (field in fieldReads) copyFieldRead(field)];

	function hasCurrentInstanceContext():Bool
		return currentMethod != null && (!currentMethod.isStatic || currentMethod.name == "new");

	function requireExactParameters(arguments:Array<TypedBackendClassMethodArgumentFact>, parameterBindings:Array<String>):Void {
		var parameterCount = 0;
		for (local in locals)
			if (local.declarationKind.match(Parameter))
				parameterCount++;
		if (parameterCount != arguments.length)
			throw "PHP function lowering plan received " + parameterCount + " exact parameter locals for " + arguments.length + " method arguments in "
				+ functionIdentity;
		for (index in 0...arguments.length) {
			final argument = arguments[index];
			final parameterIdentity = parameterBindings[index];
			var match:Null<PhpFunctionPlanLocalFact> = null;
			for (local in locals)
				if (local.bindingIdentity == parameterIdentity)
					match = local;
			if (match == null)
				throw "PHP function lowering plan cannot find exact parameter binding " + parameterIdentity + " in " + functionIdentity;
			if (!match.declarationKind.match(Parameter))
				throw "PHP function lowering plan received non-parameter binding " + parameterIdentity + " for " + argument.name;
			if (match.typeIdentity != argument.typeIdentity)
				throw "PHP function lowering plan received conflicting parameter type for " + argument.name + " in " + functionIdentity;
		}
	}

	static function semanticTypeHint(local:PhpFunctionLocalFact):String
		return local.semanticType.isUnknown() || local.semanticType.isNoNormalCompletion() ? "" : local.typeDisplay;

	static function specializedLineageHasInstanceMethod(lineage:Array<TypedBackendSpecializedClassNode>, targetName:String):Bool {
		final expected = PhpName.valueIdentifier(targetName);
		for (node in lineage)
			for (method in node.methods)
				if (!method.isStatic && PhpName.valueIdentifier(method.name) == expected)
					return true;
		return false;
	}

	static function specializedLineageHasDynamicInstanceMethod(lineage:Array<TypedBackendSpecializedClassNode>, targetName:String):Bool {
		final expected = PhpName.valueIdentifier(targetName);
		for (node in lineage)
			for (method in node.methods)
				if (!method.isStatic && method.isDynamic && PhpName.valueIdentifier(method.name) == expected)
					return true;
		return false;
	}

	static function specializedLineageFindInstanceMethodArguments(lineage:Array<TypedBackendSpecializedClassNode>,
			targetName:String):Null<Array<HxFunctionArg>> {
		final expected = PhpName.valueIdentifier(targetName);
		for (node in lineage)
			for (method in node.methods)
				if (!method.isStatic && PhpName.valueIdentifier(method.name) == expected)
					return [
						for (argument in method.arguments)
							new HxFunctionArg(argument.name, argument.typeDisplay, HxDefaultValue.NoDefault, argument.isOptional, argument.isRest)
					];
		return null;
	}

	static function specializedLineageFindInstanceField(lineage:Array<TypedBackendSpecializedClassNode>, targetName:String):Null<TypedBackendClassFieldFact> {
		final expected = PhpName.valueIdentifier(targetName);
		for (node in lineage)
			for (field in node.fields)
				if (!field.isStatic && PhpName.valueIdentifier(field.name) == expected)
					return field;
		return null;
	}

	function semanticTypeLineage(type:Null<TyType>):Null<Array<TypedBackendSpecializedClassNode>> {
		if (type == null)
			return null;
		final exactType = type.isNullable() ? type.unwrapNull() : type;
		final nominal = exactType.getNominalIdentity();
		if (nominal == null)
			return null;
		final classIdentity = nominal.getCanonicalName();
		if (classGraph.findNode(classIdentity) == null)
			return null;
		return classGraph.requireSpecializedLineageForType(exactType);
	}

	static function specializedLineageUsesPropertyAccessor(lineage:Array<TypedBackendSpecializedClassNode>, targetFieldName:String, getter:Bool):Bool {
		final expected = PhpName.valueIdentifier(targetFieldName);
		for (node in lineage)
			for (field in node.fields)
				if (!field.isStatic
					&& PhpName.valueIdentifier(field.name) == expected
					&& (getter ? field.propertyGet == "get" : field.propertySet == "set"))
					return true;
		return false;
	}

	static function buildStringExtensionOwners(programFacts:PhpProgramRenderFacts, moduleFacts:PhpModuleRenderFacts, classGraph:TypedBackendClassGraph,
			currentLineage:Array<TypedBackendSpecializedClassNode>, functionIdentity:String):haxe.ds.StringMap<String> {
		final out = new haxe.ds.StringMap<String>();
		for (providerIdentity in moduleFacts.copyUsingTypeIdentities()) {
			final providerFacts = classGraph.findClassFacts(providerIdentity);
			if (providerFacts == null)
				throw "PHP function lowering plan cannot find using provider " + providerIdentity + " for " + functionIdentity;
			final emittedOwner = programFacts.findEmittedTypeName(providerIdentity);
			if (emittedOwner == null || emittedOwner.length == 0)
				throw "PHP function lowering plan cannot find emitted using provider " + providerIdentity + " for " + functionIdentity;
			var privateVisible = false;
			for (node in currentLineage)
				if (node.classIdentity == providerIdentity) {
					privateVisible = true;
					break;
				}
			for (node in classGraph.requireSpecializedLineage(providerIdentity))
				for (method in node.methods) {
					if (!method.isStatic || method.arguments.length == 0)
						continue;
					final receiverType = method.arguments[0].semanticType.isNullable() ? method.arguments[0].semanticType.unwrapNull() : method.arguments[0].semanticType;
					if (receiverType.getSemanticKey() != "primitive:String" || (!method.isPublic && !privateVisible))
						continue;
					final targetName = PhpName.valueIdentifier(method.name);
					final previous = out.get(targetName);
					if (previous == null)
						out.set(targetName, emittedOwner);
				}
		}
		return out;
	}

	static function buildEnumConstructorCatalog(programFacts:PhpProgramRenderFacts, classGraph:TypedBackendClassGraph, moduleIdentity:String,
			functionIdentity:String):PhpFunctionPlanEnumConstructorCatalog {
		final catalog:PhpFunctionPlanEnumConstructorCatalog = {
			byName: new haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>(),
			ambiguousNames: new haxe.ds.StringMap<Bool>(),
			localByName: new haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>(),
			localAmbiguousNames: new haxe.ds.StringMap<Bool>(),
			byOwner: new haxe.ds.StringMap<haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>>(),
			byDeclaration: new haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>(),
			ownerByEmittedName: new haxe.ds.StringMap<String>()
		};
		for (node in classGraph.copyNodes()) {
			final classFacts = classGraph.findClassFacts(node.classIdentity);
			if (classFacts == null)
				throw "PHP function lowering plan cannot find class facts " + node.classIdentity + " while collecting enum constructors for "
					+ functionIdentity;
			final fields = classFacts.copyFields();
			final methods = classFacts.copyMethods();
			var isEnum = false;
			for (field in fields)
				if (field.isStatic && PhpName.valueIdentifier(field.name) == "__hx_is_enum") {
					isEnum = true;
					break;
				}
			if (!isEnum)
				for (method in methods)
					if (method.isEnumConstructor) {
						isEnum = true;
						break;
					}
			if (!isEnum)
				continue;

			final enumName = normalize(programFacts.findEmittedTypeName(node.classIdentity));
			if (enumName.length == 0)
				throw "PHP function lowering plan cannot find emitted enum " + node.classIdentity + " for " + functionIdentity;
			if (catalog.ownerByEmittedName.exists(enumName) && catalog.ownerByEmittedName.get(enumName) != node.classIdentity)
				throw "PHP function lowering plan contains conflicting emitted enum owner " + enumName;
			catalog.ownerByEmittedName.set(enumName, node.classIdentity);
			final byOwner = new haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>();
			catalog.byOwner.set(node.classIdentity, byOwner);

			for (field in fields) {
				final constructorName = PhpName.valueIdentifier(field.name);
				if (!field.isStatic || StringTools.startsWith(constructorName, "__hx_"))
					continue;
				addEnumConstructor(catalog, {
					ownerIdentity: node.classIdentity,
					moduleIdentity: node.moduleIdentity,
					declarationIdentity: field.canonicalIdentity,
					enumName: enumName,
					constructorName: constructorName,
					hasArguments: false
				}, node.moduleIdentity == moduleIdentity, functionIdentity);
			}
			for (method in methods) {
				final constructorName = PhpName.valueIdentifier(method.name);
				if (!method.isStatic
					|| !method.isEnumConstructor
					|| constructorName == "new"
					|| StringTools.startsWith(constructorName, "__hx_"))
					continue;
				addEnumConstructor(catalog, {
					ownerIdentity: node.classIdentity,
					moduleIdentity: node.moduleIdentity,
					declarationIdentity: method.canonicalIdentity,
					enumName: enumName,
					constructorName: constructorName,
					hasArguments: true
				}, node.moduleIdentity == moduleIdentity, functionIdentity);
			}
		}
		return catalog;
	}

	static function addEnumConstructor(catalog:PhpFunctionPlanEnumConstructorCatalog, fact:PhpFunctionPlanEnumConstructorFact, local:Bool,
			functionIdentity:String):Void {
		final name = fact.constructorName;
		final byOwner = catalog.byOwner.get(fact.ownerIdentity);
		if (byOwner == null)
			throw "PHP function lowering plan lost enum owner " + fact.ownerIdentity + " while collecting " + functionIdentity;
		final ownerPrevious = byOwner.get(name);
		if (ownerPrevious != null && ownerPrevious.declarationIdentity != fact.declarationIdentity)
			throw "PHP function lowering plan contains conflicting enum constructor " + fact.ownerIdentity + "." + name;
		byOwner.set(name, copyEnumConstructor(fact));

		final declarationPrevious = catalog.byDeclaration.get(fact.declarationIdentity);
		if (declarationPrevious != null && !sameEnumConstructor(declarationPrevious, fact))
			throw "PHP function lowering plan contains conflicting enum declaration " + fact.declarationIdentity;
		catalog.byDeclaration.set(fact.declarationIdentity, copyEnumConstructor(fact));

		addEnumConstructorByName(catalog.byName, catalog.ambiguousNames, fact);
		if (local)
			addEnumConstructorByName(catalog.localByName, catalog.localAmbiguousNames, fact);
	}

	static function addEnumConstructorByName(index:haxe.ds.StringMap<PhpFunctionPlanEnumConstructorFact>, ambiguous:haxe.ds.StringMap<Bool>,
			fact:PhpFunctionPlanEnumConstructorFact):Void {
		final previous = index.get(fact.constructorName);
		if (previous == null) {
			index.set(fact.constructorName, copyEnumConstructor(fact));
			return;
		}
		if (!sameEnumConstructor(previous, fact))
			ambiguous.set(fact.constructorName, true);
	}

	static function addEnumConstructorIdentity(identity:Array<Null<String>>, fact:PhpFunctionPlanEnumConstructorFact):Void {
		identity.push(fact.ownerIdentity);
		identity.push(fact.moduleIdentity);
		identity.push(fact.declarationIdentity);
		identity.push(fact.enumName);
		identity.push(fact.constructorName);
		identity.push(boolText(fact.hasArguments));
	}

	static function sameEnumConstructor(left:PhpFunctionPlanEnumConstructorFact, right:PhpFunctionPlanEnumConstructorFact):Bool
		return left.ownerIdentity == right.ownerIdentity
			&& left.moduleIdentity == right.moduleIdentity
			&& left.declarationIdentity == right.declarationIdentity
			&& left.enumName == right.enumName
			&& left.constructorName == right.constructorName
			&& left.hasArguments == right.hasArguments;

	static function copyEnumConstructor(fact:PhpFunctionPlanEnumConstructorFact):PhpFunctionPlanEnumConstructorFact
		return {
			ownerIdentity: fact.ownerIdentity,
			moduleIdentity: fact.moduleIdentity,
			declarationIdentity: fact.declarationIdentity,
			enumName: fact.enumName,
			constructorName: fact.constructorName,
			hasArguments: fact.hasArguments
		};

	static function fieldReadSortIdentity(fact:PhpFunctionPlanFieldReadFact):String
		return CompilerCacheIdentity.encode([fact.canonicalIdentity, fact.projectedName, fact.targetName]);

	static function addLineageIdentity(identity:Array<Null<String>>, node:TypedBackendSpecializedClassNode):Void {
		identity.push(node.classIdentity);
		identity.push(node.moduleIdentity);
		identity.push(node.classFactsIdentity);
		identity.push(Std.string(node.bindings.length));
		for (binding in node.bindings) {
			identity.push(binding.parameterIdentity);
			identity.push(binding.parameterName);
			identity.push(binding.typeIdentity);
			identity.push(binding.typeDisplay);
		}
		identity.push(Std.string(node.fields.length));
		for (field in node.fields)
			addFieldIdentity(identity, field);
		identity.push(Std.string(node.methods.length));
		for (method in node.methods)
			addMethodIdentity(identity, method);
	}

	static function addFieldIdentity(identity:Array<Null<String>>, field:TypedBackendClassFieldFact):Void {
		identity.push(field.canonicalIdentity);
		identity.push(field.name);
		identity.push(field.typeIdentity);
		identity.push(field.typeDisplay);
		identity.push(boolText(field.isStatic));
		identity.push(boolText(field.isPublic));
		identity.push(boolText(field.isFinal));
		identity.push(boolText(field.isInline));
		identity.push(boolText(field.hasInitializer));
		identity.push(field.propertyGet);
		identity.push(field.propertySet);
		identity.push(boolText(field.noImportGlobal));
	}

	static function addMethodIdentity(identity:Array<Null<String>>, method:TypedBackendClassMethodFact):Void {
		identity.push(method.canonicalIdentity);
		identity.push(method.name);
		identity.push(boolText(method.isStatic));
		identity.push(Std.string(method.typeParameters.length));
		for (parameter in method.typeParameters) {
			identity.push(parameter.getCanonicalKey());
			identity.push(parameter.getName());
		}
		identity.push(method.returnTypeIdentity);
		identity.push(method.returnTypeDisplay);
		identity.push(boolText(method.isPublic));
		identity.push(boolText(method.isInline));
		identity.push(boolText(method.isDynamic));
		identity.push(boolText(method.hasBody));
		identity.push(boolText(method.isEnumConstructor));
		identity.push(boolText(method.noImportGlobal));
		identity.push(Std.string(method.arguments.length));
		for (argument in method.arguments) {
			identity.push(argument.name);
			identity.push(argument.typeIdentity);
			identity.push(argument.typeDisplay);
			identity.push(boolText(argument.isOptional));
			identity.push(boolText(argument.isRest));
		}
	}

	static function copyLocal(fact:PhpFunctionPlanLocalFact):PhpFunctionPlanLocalFact
		return {
			projectedName: fact.projectedName,
			targetName: fact.targetName,
			bindingIdentity: fact.bindingIdentity,
			sourceName: fact.sourceName,
			semanticType: fact.semanticType,
			typeIdentity: fact.typeIdentity,
			typeDisplay: fact.typeDisplay,
			declarationKind: fact.declarationKind,
			isRestCarrier: fact.isRestCarrier,
			targetTypeHint: fact.targetTypeHint
		};

	static function copyFieldRead(fact:PhpFunctionPlanFieldReadFact):PhpFunctionPlanFieldReadFact
		return {
			projectedName: fact.projectedName,
			targetName: fact.targetName,
			canonicalIdentity: fact.canonicalIdentity,
			ownerIdentity: fact.ownerIdentity,
			moduleIdentity: fact.moduleIdentity,
			name: fact.name,
			semanticType: fact.semanticType,
			typeIdentity: fact.typeIdentity,
			typeDisplay: fact.typeDisplay,
			isStatic: fact.isStatic,
			isPublic: fact.isPublic,
			isFinal: fact.isFinal,
			isInline: fact.isInline,
			hasInitializer: fact.hasInitializer,
			noImportGlobal: fact.noImportGlobal
		};

	static function copyNode(node:TypedBackendSpecializedClassNode):TypedBackendSpecializedClassNode
		return {
			classIdentity: node.classIdentity,
			moduleIdentity: node.moduleIdentity,
			classFactsIdentity: node.classFactsIdentity,
			bindings: [for (binding in node.bindings) copyBinding(binding)],
			fields: [for (field in node.fields) copyField(field)],
			methods: [for (method in node.methods) copyMethod(method)]
		};

	static function copyBinding(binding:TypedBackendClassTypeBinding):TypedBackendClassTypeBinding
		return {
			parameterIdentity: binding.parameterIdentity,
			parameterName: binding.parameterName,
			semanticType: binding.semanticType,
			typeIdentity: binding.typeIdentity,
			typeDisplay: binding.typeDisplay
		};

	static function copyField(field:TypedBackendClassFieldFact):TypedBackendClassFieldFact
		return {
			canonicalIdentity: field.canonicalIdentity,
			name: field.name,
			semanticType: field.semanticType,
			typeIdentity: field.typeIdentity,
			typeDisplay: field.typeDisplay,
			isStatic: field.isStatic,
			isPublic: field.isPublic,
			isFinal: field.isFinal,
			isInline: field.isInline,
			hasInitializer: field.hasInitializer,
			propertyGet: field.propertyGet,
			propertySet: field.propertySet,
			noImportGlobal: field.noImportGlobal
		};

	static function copyMethod(method:TypedBackendClassMethodFact):TypedBackendClassMethodFact
		return {
			canonicalIdentity: method.canonicalIdentity,
			name: method.name,
			isStatic: method.isStatic,
			typeParameters: method.typeParameters.copy(),
			arguments: [
				for (argument in method.arguments)
					{
						name: argument.name,
						semanticType: argument.semanticType,
						typeIdentity: argument.typeIdentity,
						typeDisplay: argument.typeDisplay,
						isOptional: argument.isOptional,
						isRest: argument.isRest
					}
			],
			returnSemanticType: method.returnSemanticType,
			returnTypeIdentity: method.returnTypeIdentity,
			returnTypeDisplay: method.returnTypeDisplay,
			isPublic: method.isPublic,
			isInline: method.isInline,
			isDynamic: method.isDynamic,
			hasBody: method.hasBody,
			isEnumConstructor: method.isEnumConstructor,
			noImportGlobal: method.noImportGlobal
		};

	static function normalize(value:Null<String>):String
		return value == null ? "" : StringTools.trim(value);

	static function boolText(value:Bool):String
		return value ? "true" : "false";
}
