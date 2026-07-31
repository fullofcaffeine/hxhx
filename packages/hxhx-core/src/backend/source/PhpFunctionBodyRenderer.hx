package backend.source;

import backend.source.PhpFunctionLoweringPlan.PhpFunctionPlanEnumConstructorFact;

/**
	Request-owned renderer for one exact PHP executable unit.

	The ordinary unit is a function body. A typed field initializer is also an
	executable unit because it may contain lambdas, local bindings, and field
	reads. The renderer binds immutable program, module, class, unit, body,
	local, field-read, and inheritance facts before syntax rendering begins.
	Recursive rendering receives a `PhpLexicalRenderScope` through the shared
	render-frame adapter. This facts owner does not call the shared syntax
	kernel, which keeps the generated OCaml dependency graph acyclic.
**/
class PhpFunctionBodyRenderer {
	final programRenderer:PhpProgramBodyRenderer;
	final programFacts:PhpProgramRenderFacts;
	final moduleFacts:PhpModuleRenderFacts;
	final plan:PhpFunctionLoweringPlan;

	public function new(programRenderer:PhpProgramBodyRenderer, programFacts:PhpProgramRenderFacts, moduleFacts:PhpModuleRenderFacts,
			plan:PhpFunctionLoweringPlan) {
		if (programRenderer == null || programFacts == null || moduleFacts == null || plan == null)
			throw "PHP function body renderer requires complete immutable facts";
		if (programFacts.getProgramRevision() != plan.getProgramRevision()
			|| moduleFacts.getProgramRevision() != plan.getProgramRevision()
			|| moduleFacts.getModuleRevision() != plan.getModuleRevision()
			|| moduleFacts.getModuleIdentity() != plan.getModuleIdentity())
			throw "PHP function body renderer received facts from different program or module revisions";
		if (programRenderer.getProgramFacts().getCanonicalIdentity() != programFacts.getCanonicalIdentity()
			|| programRenderer.requireModuleFacts(moduleFacts.getModuleIdentity()).getCanonicalIdentity() != moduleFacts.getCanonicalIdentity())
			throw "PHP function body renderer received a program renderer from different sealed facts";
		this.programRenderer = programRenderer;
		this.programFacts = programFacts;
		this.moduleFacts = moduleFacts;
		this.plan = plan;
	}

	public function getProgramRenderer():PhpProgramBodyRenderer
		return programRenderer;

	public function getProgramFacts():PhpProgramRenderFacts
		return programFacts;

	public function getModuleFacts():PhpModuleRenderFacts
		return moduleFacts;

	public function getPlan():PhpFunctionLoweringPlan
		return plan;

	/** Return the exact emitted name of a type declared in the active source module. **/
	public function findLocalTypeName(sourceName:String):Null<String>
		return moduleFacts.findLocalTypeName(sourceName);

	/** Return the exact PHP name selected by a resolved type import. **/
	public function findImportedTypeAlias(sourceName:String):Null<String>
		return moduleFacts.findImportedTypeAlias(sourceName);

	/** Return an exact emitted type name from the sealed program catalog. **/
	public function findEmittedTypeName(sourceName:String):Null<String>
		return programFacts.findEmittedTypeName(sourceName);

	/** Return the exact current-class instance-field type used by assignment lowering. **/
	public function findInstanceFieldTypeHint(targetName:String):Null<String>
		return plan.findInstanceFieldTypeHint(targetName);

	/** Report whether the active method is one accessor for the named property. **/
	public function isCurrentPropertyAccessor(targetFieldName:String):Bool
		return plan.isCurrentPropertyAccessor(targetFieldName);

	/** Report whether the active class lineage exposes an instance method. **/
	public function hasCurrentInstanceMethod(targetName:String):Bool
		return plan.hasCurrentInstanceMethod(targetName);

	/** Return exact arguments for one method on the active class lineage. **/
	public function findCurrentInstanceMethodArguments(targetName:String):Null<Array<HxFunctionArg>>
		return plan.findCurrentInstanceMethodArguments(targetName);

	/** Report whether the active class lineage exposes an instance field. **/
	public function hasCurrentInstanceField(targetName:String):Bool
		return plan.hasCurrentInstanceField(targetName);

	/** Return exact current-lineage instance methods for the pre-render rewrite. **/
	public function copyCurrentInstanceMethodTargetNames():haxe.ds.StringMap<Bool>
		return plan.copyCurrentInstanceMethodTargetNames();

	/** Return exact current-lineage instance fields for the pre-render rewrite. **/
	public function copyCurrentInstanceFieldTargetNames():haxe.ds.StringMap<Bool>
		return plan.copyCurrentInstanceFieldTargetNames();

	/** Return exact current-class static members for the pre-render rewrite. **/
	public function copyCurrentClassStaticMemberTargetNames():haxe.ds.StringMap<Bool>
		return plan.copyCurrentClassStaticMemberTargetNames();

	/** Return exact parameter target names that shadow same-class members. **/
	public function copyParameterTargetNames():Array<String>
		return plan.copyParameterTargetNames();

	/** Report whether an exact semantic local type exposes an instance method. **/
	public function semanticTypeHasInstanceMethod(type:Null<TyType>, targetName:String):Bool
		return plan.semanticTypeHasInstanceMethod(type, targetName);

	/** Return exact arguments for one method on an exact semantic receiver type. **/
	public function semanticTypeInstanceMethodArguments(type:Null<TyType>, targetName:String):Null<Array<HxFunctionArg>>
		return plan.semanticTypeInstanceMethodArguments(type, targetName);

	/** Report whether an exact semantic local type inherits a dynamic method. **/
	public function semanticTypeHasDynamicInstanceMethod(type:Null<TyType>, targetName:String):Bool
		return plan.semanticTypeHasDynamicInstanceMethod(type, targetName);

	/** Report whether an exact semantic local type exposes an instance field. **/
	public function semanticTypeHasInstanceField(type:Null<TyType>, targetName:String):Bool
		return plan.semanticTypeHasInstanceField(type, targetName);

	/** Report whether an exact generic-specialized local field is callable. **/
	public function semanticTypeHasCallableInstanceField(type:Null<TyType>, targetName:String):Bool
		return plan.semanticTypeHasCallableInstanceField(type, targetName);

	/** Return the exact generic-specialized field type used for call alignment. **/
	public function semanticTypeInstanceFieldTypeHint(type:Null<TyType>, targetName:String):Null<String>
		return plan.semanticTypeInstanceFieldTypeHint(type, targetName);

	/** Report whether an exact semantic local field uses a Haxe getter. **/
	public function semanticTypeUsesPropertyGetter(type:Null<TyType>, targetFieldName:String):Bool
		return plan.semanticTypeUsesPropertyGetter(type, targetFieldName);

	/** Report whether an exact semantic local field uses a Haxe setter. **/
	public function semanticTypeUsesPropertySetter(type:Null<TyType>, targetFieldName:String):Bool
		return plan.semanticTypeUsesPropertySetter(type, targetFieldName);

	/** Return the exact PHP local used to instantiate one method type parameter. **/
	public function findGenericConstructorSampleTargetName(typeParameterName:String):Null<String>
		return plan.findGenericConstructorSampleTargetName(typeParameterName);

	/** Return the exact module-visible owner for one String extension method. **/
	public function findStringExtensionOwner(targetName:String):Null<String>
		return plan.findStringExtensionOwner(targetName);

	/** Resolve an enum constructor from sealed program facts and an optional exact owner. **/
	public function findEnumConstructor(targetName:String, ?preferredOwnerIdentity:String):Null<PhpFunctionPlanEnumConstructorFact>
		return plan.findEnumConstructor(targetName, preferredOwnerIdentity);

	/** Resolve an already-selected exact enum-constructor marker. **/
	public function requireExactEnumConstructor(ownerIdentity:String, modulePath:String, declarationIdentity:String,
			constructorName:String):PhpFunctionPlanEnumConstructorFact
		return plan.requireExactEnumConstructor(ownerIdentity, modulePath, declarationIdentity, constructorName);

	/** Return the exact enum owner carried by one semantic local type. **/
	public function findEnumOwnerIdentity(type:Null<TyType>):Null<String>
		return plan.findEnumOwnerIdentity(type);

	/** Return exact planned local representation hints in target-name space. **/
	public function copyLocalTypeHints():haxe.ds.StringMap<String> {
		final out = new haxe.ds.StringMap<String>();
		for (local in plan.copyLocals())
			out.set(local.targetName, local.targetTypeHint);
		return out;
	}
}
