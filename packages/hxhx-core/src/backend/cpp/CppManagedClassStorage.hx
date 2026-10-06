package backend.cpp;

import TypedBackendClassSemanticFacts.TypedBackendClassFieldFact;
import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;
import backend.cpp.CppManagedCallContext.CppManagedCallOwner;

/** Each occurrence retains its lexical owner independently of a later concrete application. */
private typedef ManagedOccurrenceOwner<T> = {
	final source:CppManagedCallOwner;
	final find:Void->T;
}

/** One physical layout retains its exact semantic owner, never a reflected display name. */
typedef CppManagedClassLayout = {
	final owner:TypedBackendClassProjection;
	final type:TyType;
	final symbol:String;
	final fields:Array<TypedBackendClassFieldFact>;
	final declaredFields:Array<TypedBackendClassFieldFact>;
	final parent:Null<String>;
}

/** Identity exists independently of whether this request can allocate an instance. */
private typedef CppManagedClassDescriptorEntry = {
	final owner:TypedBackendClassProjection;
	final symbol:String;
	var layout:Null<CppManagedClassLayout>;
	var runtimeKind:Null<TypedRuntimeTypeKind>;
}

/** A selected field keeps its declaration type and checked offset together. */
typedef CppManagedInstanceMember = {
	final layout:CppManagedClassLayout;
	final slot:Int;
	final fact:TypedBackendClassFieldFact;
	final declaredType:TyType;
	final storedType:TyType;
}

/**
	Plan ordinary managed class storage from exact program-owned declarations.
	This physical descriptor table is the owner for admitted instance layouts;
	future class-value consumers must reuse it, not create another native registry.
	Shared runtime-type occurrence planning remains in CppRuntimeTypePlan.
	Applied field facts remain separate from shared physical declaration offsets.
	Extern adapters, interfaces, and properties require explicit plans.
	Authored field initialization remains separate from physical layout defaults.
 */
class CppManagedClassStorage {
	final program:CppTypedProgramProjection;
	final descriptors:Array<CppManagedClassDescriptorEntry> = [];
	final layouts:CppManagedClassLayouts;
	var hasInstanceTypeTests:Bool = false;

	/** Method calls share this program's exact owners and physical descriptors. */
	public final methods:CppManagedMethods;

	/** Standard conversion shares these exact descriptors and ordinary method applications. */
	public final strings:CppManagedStringMethods;

	/** One exact program resolves both abstract storage and typed transfer boundaries. */
	public final casts:CppManagedCastPlan;

	final runtimeOwners = new haxe.ds.ObjectMap<TypedBackendRuntimeTypeOccurrence, ManagedOccurrenceOwner<TypedBackendRuntimeTypeOccurrence>>();
	final constructorOwners = new haxe.ds.ObjectMap<TypedBackendConstructorOccurrence, ManagedOccurrenceOwner<TypedBackendConstructorOccurrence>>();
	final catchOwners = new haxe.ds.ObjectMap<TypedCatchUse, Void->Void>();

	public function new(program:CppTypedProgramProjection) {
		if (program == null)
			throw 'managed class storage requires an exact program';
		this.program = program;
		program.assertCurrent();
		casts = new CppManagedCastPlan(program);
		methods = new CppManagedMethods(program, this);
		layouts = new CppManagedClassLayouts(program, owner -> descriptor(owner).symbol, publishLayout);
		strings = new CppManagedStringMethods(program, this);
		for (module in program.getModules())
			for (owner in module.projection.getClasses()) {
				for (fn in owner.getFunctions()) {
					registerCatches(fn.getLocalCatalog(), () -> fn.requireCaptureCatalog().assertCurrent());
					for (entry in fn.getRuntimeTypeCatalog().getEntries())
						runtimeOwners.set(entry, {source: FunctionSource(fn), find: () -> fn.requireRuntimeType(entry.getExpression())});
					for (entry in fn.getConstructorCatalog().getEntries())
						constructorOwners.set(entry, {source: FunctionSource(fn), find: () -> fn.requireConstructor(entry.getExpression())});
				}
				for (initializer in owner.getFieldInitializers()) {
					registerCatches(initializer.getLocalCatalog(), () -> initializer.assertCurrent());
					for (entry in initializer.getRuntimeTypeCatalog().getEntries())
						runtimeOwners.set(entry, {source: FieldSource(initializer), find: () -> initializer.requireRuntimeType(entry.getExpression())});
					for (entry in initializer.getConstructorCatalog().getEntries())
						constructorOwners.set(entry, {source: FieldSource(initializer), find: () -> initializer.requireConstructor(entry.getExpression())});
				}
			}
	}

	/** Implicit payload reads belong to the same exact lexical catalogs as explicit source operations. */
	function registerCatches(catalog:TypedBackendLocalCatalog, validate:Void->Void):Void {
		for (local in catalog.getEntries()) {
			final binding = local.getBinding();
			final identity = binding.getIdentity().getCanonicalKey();
			final use = catalog.findCatchUse(identity);
			if (use != null)
				catchOwners.set(use, () -> {
					validate();
					if (catalog.findCatchUse(identity) != use || use.binding != binding)
						throw "managed catch payload requires its exact implicit use";
				});
		}
	}

	/**
		Use the real ValueException field and ordinary class layout for implicit unwrapping.
		The nominal predicate must succeed before native code reads this slot. No
		synthetic source field or runtime-type occurrence can authorize the access.
	 */
	public function catchPayload(use:TypedCatchUse):CppManagedInstanceMember {
		final validate = catchOwners.get(use);
		if (validate == null)
			throw "managed catch payload belongs to another program or implicit use";
		validate();
		if (use.view != OrdinaryValue || use.payload == null)
			throw "managed catch payload requires an ordinary-value view";
		final field = use.payload;
		final member = storedMember(field, TyType.nominal(field.getOwner(), []), field.getType());
		final entry = descriptor(member.layout.owner);
		entry.runtimeKind = Nominal(field.getOwner());
		hasInstanceTypeTests = true;
		return member;
	}

	/**
		The caller may substitute only an operation in its exact executable catalog.
		Program planning and publication validate the complete typed source; repeating
		that scan for every operand would also revisit unrelated provider bodies.
	 */
	function assertRuntimeContext(occurrence:TypedBackendRuntimeTypeOccurrence, context:Null<CppManagedEnclosingApplication>):Void {
		final requireOwner = runtimeOwners.get(occurrence);
		if (requireOwner == null || requireOwner.find() != occurrence)
			throw "managed class value belongs to another program or occurrence";
		occurrence.assertCurrent();
		CppManagedCallContext.assertOwner(context, requireOwner.source);
	}

	/** Resolve the tested value through its lexical caller without changing the shared runtime target. */
	public function runtimeOperandType(occurrence:TypedBackendRuntimeTypeOccurrence, ?context:CppManagedEnclosingApplication):TyType {
		assertRuntimeContext(occurrence, context);
		final type = occurrence.getValueType();
		if (type == null)
			throw "managed runtime operand requires a value test";
		return context == null
			|| TyTypeSubstitution.parameterIdentities(type).length == 0 ? type : CppManagedCallContext.resolveType(context, type);
	}

	/** Class handles reuse instance identity without admitting an unsupported native layout. */
	public function requireRuntimeDescriptor(occurrence:TypedBackendRuntimeTypeOccurrence, ?context:CppManagedEnclosingApplication):String {
		program.assertCurrent();
		assertRuntimeContext(occurrence, context);
		if (occurrence.getValue() != null)
			throw "managed class value requires a descriptor occurrence";
		final target = occurrence.getTarget();
		switch target.getKind() {
			case ArrayCore | StringCore | Nominal(_):
			case _:
				throw "managed class value requires an explicit meta-value representation";
		}
		final owner = program.requireClass(program.requireClassIdentity(target.requireDeclarationIdentity().getCanonicalName()));
		switch owner.requireSemanticFacts().getNominalKind() {
			case ClassInstance:
			case _:
				throw "managed class value requires a class declaration";
		}
		final entry = descriptor(owner);
		entry.runtimeKind = target.getKind();
		return entry.symbol;
	}

	/**
		Select an ordinary class or interface test from its exact runtime occurrence.
		Other target families retain their separate representation plans. An opaque
		operand is safe here: generated checks validate its tag and physical layout.
	 */
	public function instanceTestDescriptor(occurrence:TypedBackendRuntimeTypeOccurrence, ?context:CppManagedEnclosingApplication):Null<String> {
		if (occurrence.getValue() == null)
			throw "managed instance test requires a value operand";
		final identity = switch occurrence.getTarget().getKind() {
			case Nominal(identity): identity;
			case _: return null;
		};
		final owner = program.requireClass(program.requireClassIdentity(identity.getCanonicalName()));
		final facts = owner.requireSemanticFacts();
		if (facts.getIsExtern() || !facts.getNominalKind().match(ClassInstance))
			return null;
		CppManagedClosureAbi.assertComplete(runtimeOperandType(occurrence, context));
		final entry = descriptor(owner);
		entry.runtimeKind = occurrence.getTarget().getKind();
		hasInstanceTypeTests = true;
		return entry.symbol;
	}

	/** Direct type-test syntax shares the same predicate as the standard library call. */
	public function needsRuntimePredicate():Bool
		return hasInstanceTypeTests;

	function descriptor(owner:TypedBackendClassProjection):CppManagedClassDescriptorEntry {
		for (entry in descriptors)
			if (entry.owner == owner)
				return entry;
		final entry:CppManagedClassDescriptorEntry = {
			owner: owner,
			symbol: "hxhx_class_" + descriptors.length,
			layout: null,
			runtimeKind: null
		};
		descriptors.push(entry);
		return entry;
	}

	public function assertFunction(projection:TypedBackendFunctionProjection):Void {
		program.assertCurrent();
		assertFunctionOwner(projection);
	}

	/** Local application checks use exact membership; program emission checks all module revisions at its boundaries. */
	@:allow(backend.cpp.CppManagedMethods)
	function assertFunctionOwner(projection:TypedBackendFunctionProjection):Void {
		final declaration = projection.getDeclaration();
		if (program.requireFunction(program.requireFunctionOwner(declaration), declaration) != projection)
			throw 'managed class access belongs to another function projection';
	}

	public function assertInitializer(projection:TypedBackendFieldInitializerProjection):Void {
		program.assertCurrent();
		assertInitializerOwner(projection);
	}

	/**
		Application reuse checks this field's exact membership and projected source.
		Its capture catalog separately validates the authored body and closures.
		Creation and emission retain the complete program revision checks, without
		rescanning unrelated standard-library bodies for every type substitution.
	 */
	function assertInitializerOwner(projection:TypedBackendFieldInitializerProjection):Void {
		projection.assertCurrent();
		final owner = program.requireClassIdentity(projection.getField().getOwner().getCanonicalName());
		if (program.requireInitializer(owner, projection.getDeclaration()) != projection)
			throw 'managed construction belongs to another initializer projection';
	}

	/** Only the program's complete core Class<T> type selects descriptor comparison. */
	public function isClassValue(type:TyType):Bool {
		CppManagedClosureAbi.assertComplete(type);
		var selected = type;
		while (selected.getNullableInner() != null)
			selected = selected.getNullableInner();
		return CppManagedClassValueType.selects(program, selected);
	}

	/** Class and interface views retain allocation identity; an interface view never allocates its own payload. */
	public function isInstanceValue(type:TyType):Bool {
		CppManagedClosureAbi.assertComplete(type);
		final selected = type.getNullableInner() == null ? type : type.getNullableInner();
		if (selected.getNominalIdentity() == null || TyTypeSubstitution.parameterIdentities(selected).length != 0)
			return false;
		final owner = program.requireClass(program.requireClassIdentity(selected.getNominalIdentity().getCanonicalName()));
		final facts = owner.requireSemanticFacts();
		return switch facts.getNominalKind() {
			case ClassInstance: !facts.getIsExtern();
			case _: false;
		};
	}

	/** The owned Array literal is contextually polymorphic; a stored Class<Array<Dynamic>> is not. */
	public function acceptsArrayLiteral(occurrence:Null<TypedBackendRuntimeTypeOccurrence>, target:TyType):Bool {
		if (occurrence == null || occurrence.getValue() != null)
			return false;
		switch occurrence.getTarget().getKind() {
			case ArrayCore:
			case _:
				return false;
		}
		if (CppManagedClassValueType.arrayElement(program, target) == null)
			return false;
		requireRuntimeDescriptor(occurrence);
		return true;
	}

	/** Only fully represented class instances can allocate this physical payload. */
	public function requireType(type:TyType):CppManagedClassLayout {
		return layouts.requireType(type);
	}

	/** Applications share physical offsets only after their exact declared field inventories agree. */
	function publishLayout(layout:CppManagedClassLayout):Void {
		final entry = descriptor(layout.owner);
		if (entry.layout != null) {
			if (entry.layout.parent != layout.parent || entry.layout.fields.length != layout.fields.length)
				throw "applied class changed its physical inheritance layout";
			for (index in 0...layout.fields.length)
				if (entry.layout.fields[index].canonicalIdentity != layout.fields[index].canonicalIdentity)
					throw "applied class changed a physical field offset";
		} else {
			entry.layout = layout;
		}
	}

	/** Identify an exact nongeneric abstract constructor without allocating ordinary instance layout. */
	public function abstractConstructorUnderlying(projection:TypedBackendFunctionProjection):Null<TyType> {
		assertFunction(projection);
		final declaration = projection.requireSemanticDeclaration();
		if (declaration.getIsStatic() || declaration.getSignature().getName() != 'new')
			return null;
		final owner = program.requireClass(program.requireClassIdentity(declaration.getOwner().getCanonicalName()));
		final facts = owner.requireSemanticFacts();
		return switch facts.getNominalKind() {
			case AbstractValue(underlying):
				if (facts.getIsExtern()
					|| facts.getTypeParameterIds().length != 0
					|| !declaration.getHasBody()
					|| !projection.getReturnType().isVoid())
					throw 'managed abstract construction requires an exact nongeneric authored Void body';
				CppManagedClosureAbi.assertComplete(underlying);
				underlying;
			case _: null;
		};
	}

	/** Constructed value and authored Void constructor body are distinct typed results. */
	public function requireConstructor(occurrence:TypedBackendConstructorOccurrence, ?context:CppManagedEnclosingApplication):TypedBackendFunctionProjection {
		final selected = constructorApplication(occurrence, context);
		final type = CppManagedCallContext.resolveType(context, occurrence.getConstructedType());
		if (selected.backingType == null)
			requireType(type);
		return selected.projection;
	}

	/** An exact parent call may initialize only the immediate superclass of its enclosing constructor. */
	public function assertSuperConstructor(projection:TypedBackendFunctionProjection, occurrence:TypedBackendConstructorOccurrence):Void {
		assertFunction(projection);
		final declaration = projection.requireSemanticDeclaration();
		if (!occurrence.getIsSuperCall()
			|| projection.requireConstructor(occurrence.getExpression()) != occurrence
			|| declaration.getIsStatic()
			|| declaration.getSignature().getName() != "new")
			throw "parent call requires its exact enclosing constructor";
		final owner = program.requireClass(program.requireClassIdentity(declaration.getOwner().getCanonicalName()));
		final facts = owner.requireSemanticFacts();
		program.getClassGraph().requireLineage(facts.getClassIdentity());
		final parent = facts.getSuperType();
		if (parent == null || parent.getSemanticKey() != occurrence.getConstructedType().getSemanticKey())
			throw "parent call selected another superclass";
	}

	/** Bare fields retain their declaring owner while borrowing the enclosing class's instance receiver. */
	public function implicitFieldReceiverType(projection:TypedBackendFunctionProjection, occurrence:TypedBackendFieldOccurrence):TyType {
		assertImplicitFieldReceiver(projection, occurrence);
		final identity = projection.requireSemanticDeclaration().getOwner();
		final facts = program.requireClass(program.requireClassIdentity(identity.getCanonicalName())).requireSemanticFacts();
		return TyType.nominal(identity, [for (parameter in facts.getTypeParameterIds()) TyType.typeParameter(parameter)]);
	}

	/** A bare access must belong to this exact instance body and its class ancestry. */
	public function assertImplicitFieldReceiver(projection:TypedBackendFunctionProjection, occurrence:TypedBackendFieldOccurrence):Void {
		assertFunction(projection);
		final declaration = projection.requireSemanticDeclaration();
		if (declaration.getIsStatic()
			|| occurrence.getReceiver() != ImplicitOwner
			|| projection.findField(occurrence.getExpression()) != occurrence
			|| occurrence.getField().getIsStatic())
			throw "implicit field receiver requires its exact instance occurrence";
		final declaredOwner = occurrence.getField().getOwner();
		if (declaredOwner.equals(declaration.getOwner()))
			return;
		final ancestors = program.getClassGraph().requireLineage(declaration.getOwner().getCanonicalName());
		if (ancestors.filter(node -> node.classIdentity == declaredOwner.getCanonicalName()).length == 0)
			throw "implicit field receiver belongs to another class family";
	}

	/**
		Resolve an exact constructor application's types without promising its physical
		storage or emitted entry. Generic execution additionally needs this same view
		through body storage, call closure planning, and native symbol allocation.
	 */
	public function constructorApplication(occurrence:TypedBackendConstructorOccurrence,
			?context:CppManagedEnclosingApplication):CppManagedFunctionApplication {
		program.assertCurrent();
		final lexical = constructorOwners.get(occurrence);
		if (lexical == null || lexical.find() != occurrence)
			throw "managed constructor belongs to another program or occurrence";
		CppManagedCallContext.assertOwner(context, lexical.source);
		// The caller resolves its own binders before the selected constructor binds
		// its declaring class. Concrete facts do not need repeated substitution.
		function appliedType(type:TyType):TyType
			return context == null
				|| TyTypeSubstitution.parameterIdentities(type).length == 0 ? type : CppManagedCallContext.resolveType(context, type);
		final application = occurrence.requireApplication();
		final type = appliedType(occurrence.getConstructedType());
		CppManagedClosureAbi.assertComplete(type);
		if (type.getNominalIdentity() == null)
			throw "managed constructor application requires an exact nominal owner";
		final ownerType = appliedType(application.getOwnerType());
		final owner = program.requireClass(program.requireClassIdentity(ownerType.getNominalIdentity().getCanonicalName()));
		final facts = owner.requireSemanticFacts();
		if (facts.getIsExtern() || facts.getIsInterface())
			throw "managed constructor application requires an authored owner: " + facts.getClassIdentity();
		for (projection in owner.getFunctions()) {
			final declaration = projection.requireSemanticDeclaration();
			if (declaration != application.getDeclaration())
				continue;
			if (declaration.getIsStatic()
				|| declaration.getIsDynamic()
				|| !declaration.getHasBody()
				|| declaration.getTypeParameters().length != 0
				|| declaration.getSignature().getName() != "new"
				|| !projection.getReturnType().isVoid())
				throw "managed constructor application requires its exact authored Void body";
			final backing = switch facts.getNominalKind() {
				case AbstractValue(type): type;
				case ClassInstance: null;
				case _: throw "managed constructor application requires a class or abstract";
			};
			final selected = new CppManagedFunctionApplication({
				projection: projection,
				receiverType: ownerType,
				forwardedTypes: [for (forwarded in application.getForwardedTypes()) appliedType(forwarded)],
				parameters: facts.getTypeParameterIds(),
				backingType: backing,
				casts: casts,
				validate: () -> {
					if (lexical.find() != occurrence)
						throw "managed constructor occurrence changed";
					CppManagedCallContext.assertCurrent(context);
					assertFunctionOwner(projection);
				}
			});
			final underlying = application.getUnderlyingType() == null ? null : appliedType(application.getUnderlyingType());
			if ((selected.backingType == null) != (underlying == null)
				|| (selected.backingType != null && selected.backingType.getSemanticKey() != underlying.getSemanticKey()))
				throw "managed constructor application backing disagrees with shared selection";
			final parameters = selected.parameterTypes();
			final written = HxFunctionDecl.getArgs(declaration.getSourceDeclaration());
			final applied = application.getParameterTypes();
			final expected = [
				for (index in 0...applied.length)
					TyFunctionParameter.declarationBodyType(appliedType(applied[index]), written[index])
			];
			final slots = occurrence.requireArgumentBinding().getSlots();
			if (parameters.length != expected.length || slots.length != parameters.length)
				throw "managed constructor application parameters disagree with shared argument mapping";
			for (slot in slots)
				switch slot {
					case Omitted | Supplied(_):
					case RestElements(_) | RestSpread(_):
						throw "managed constructor rest arguments require explicit container transport";
				}
			for (index in 0...parameters.length)
				if (parameters[index].getSemanticKey() != expected[index].getSemanticKey())
					throw "managed constructor application parameters disagree with shared selection";
			if (backing == null && !occurrence.getIsSuperCall()) {
				methods.registerAllocation(type);
			}
			return selected;
		}
		throw "managed constructor application lacks its exact program body";
	}

	/** Field identity, declaration object, applied type, and physical slot must agree. */
	public function member(occurrence:TypedBackendFieldOccurrence, receiverType:TyType, fieldType:TyType):CppManagedInstanceMember {
		final field = occurrence.getField();
		if ((field.getPropertyGet() == 'get' || field.getPropertySet() == 'set') && !occurrence.getHasPropertyStorageAccess())
			throw 'managed instance property requires shared accessor or backing-storage selection';
		if (field.getIsStatic() || occurrence.getReceiver() == TypeQualifier)
			throw 'managed instance access requires an instance field';
		if (TyTypeSubstitution.parameterIdentities(occurrence.getType()).length == 0
			&& occurrence.getType().getSemanticKey() != fieldType.getSemanticKey())
			throw "managed instance field cannot change a concrete occurrence type";
		return storedMember(field, receiverType, fieldType);
	}

	/** Explicit occurrences and checked implicit uses share declaration identity and physical offsets. */
	function storedMember(field:TyFieldInfo, receiverType:TyType, fieldType:TyType):CppManagedInstanceMember {
		final owner = program.requireClass(program.requireClassIdentity(field.getOwner().getCanonicalName()));
		final declared = owner.requireSemanticFacts().requireField(field);
		final layout = requireType(receiverType.getNullableInner() == null ? receiverType : receiverType.getNullableInner());
		for (index in 0...layout.fields.length) {
			final fact = layout.fields[index];
			if (fact.canonicalIdentity != declared.canonicalIdentity)
				continue;
			if (fact.typeIdentity != fieldType.getSemanticKey())
				throw 'managed instance field requires its exact applied type';
			return {
				layout: layout,
				slot: index,
				fact: fact,
				declaredType: declared.semanticType,
				storedType: CppManagedAppliedStorage.fromApplied(declared.semanticType, fact.semanticType, casts)
			};
		}
		throw 'managed instance field has no allocated slot';
	}

	/** Execute constructor-free child fields first, then the declared owner's fields, reversing each class's declarations. */
	public function constructorInitializers(projection:TypedBackendFunctionProjection,
			?application:CppManagedFunctionApplication):Array<CppManagedInitializerApplication> {
		assertFunction(projection);
		if (application != null && application.projection != projection)
			throw "constructor initializers belong to another application";
		final declaration = projection.requireSemanticDeclaration();
		if (declaration.getIsStatic() || declaration.getSignature().getName() != "new")
			return [];
		final owner = program.requireClass(program.requireClassIdentity(declaration.getOwner().getCanonicalName()));
		switch owner.requireSemanticFacts().getNominalKind() {
			case ClassInstance:
			case _:
				return [];
		}
		final types = application == null ? [] : application.getForwardedTypes();
		types.push(application == null ? TyType.nominal(declaration.getOwner(), []) : application.receiverType);
		final result = new Array<CppManagedInitializerApplication>();
		for (type in types) {
			final selected = program.requireClass(program.requireClassIdentity(type.getNominalIdentity().getCanonicalName()));
			final initializers = selected.getFieldInitializers().filter(entry -> !entry.getField().getIsStatic());
			initializers.reverse();
			for (initializer in initializers) {
				final applied = initializerApplication(initializer, type);
				initializerMember(applied);
				result.push(applied);
			}
		}
		return result;
	}

	/** Field identity and declaring class arguments jointly select an initializer application. */
	public function initializerApplication(projection:TypedBackendFieldInitializerProjection, ownerType:TyType):CppManagedInitializerApplication {
		assertInitializer(projection);
		final field = projection.getField();
		if (ownerType == null || ownerType.getNominalIdentity() == null || !ownerType.getNominalIdentity().equals(field.getOwner()))
			throw "initializer application requires its exact declaring class";
		final owner = program.requireClass(program.requireClassIdentity(field.getOwner().getCanonicalName()));
		return new CppManagedInitializerApplication({
			projection: projection,
			ownerType: ownerType,
			parameters: owner.requireSemanticFacts().getTypeParameterIds(),
			casts: casts,
			validate: () -> assertInitializerOwner(projection)
		});
	}

	/** An initializer can write a final field only through its own current declaration and allocated slot. */
	public function initializerMember(application:CppManagedInitializerApplication):CppManagedInstanceMember {
		application.assertCurrent();
		final projection = application.projection;
		assertInitializer(projection);
		final field = projection.getField();
		if (field.getIsStatic() || field.getIsInline())
			throw "managed instance initializer requires an ordinary stored field";
		final layout = requireType(application.ownerType);
		final fact = layout.owner.requireSemanticFacts().requireField(field);
		if (!fact.hasStorage || !fact.hasInitializer)
			throw "managed instance initializer requires its exact storage declaration";
		for (index in 0...layout.fields.length)
			if (layout.fields[index].canonicalIdentity == fact.canonicalIdentity)
				return {
					layout: layout,
					slot: index,
					fact: layout.fields[index],
					declaredType: fact.semanticType,
					storedType: CppManagedAppliedStorage.fromApplied(fact.semanticType, layout.fields[index].semanticType, casts)
				};
		throw "managed instance initializer has no allocated slot";
	}

	/** The Haxe plan supplies every default before the native constructor receives control. */
	public function defaults(type:TyType):Array<String> {
		final layout = requireType(type);
		return [
			for (index in 0...layout.fields.length)
				layout.declaredFields[index].semanticType.isTypeParameter() ? "hxhx::managed::Value{}" : CppManagedStaticDefault.render(program,
					CppManagedAppliedStorage.fromApplied(layout.declaredFields[index].semanticType, layout.fields[index].semanticType, casts))
		];
	}

	/** Emit identity-only entries explicitly; they cannot be used by InstancePayload. */
	public function render():String {
		program.assertCurrent();
		final declarations = [
			for (entry in descriptors)
				'extern const hxhx::managed::ClassDescriptor ' + entry.symbol + ';'
		];
		return declarations.concat([
			for (entry in descriptors)
				'inline const hxhx::managed::ClassDescriptor '
				+ entry.symbol
				+ ' = {'
				+ CppManagedText.quotedBytes(entry.owner.requireSemanticFacts().getClassIdentity())
				+ ', '
				+ (entry.layout == null ? 'false, 0' : 'true, ' + entry.layout.fields.length)
				+ ', '
				+ (entry.layout == null || entry.layout.parent == null ? 'nullptr' : '&' + entry.layout.parent)
				+ '};']).join('\n');
	}

	/**
		Emit membership only after all bodies have selected their exact descriptors.
		Physical layout tests authorize payload reads; nominal membership compares
		the descriptor attached by the admitted constructor. Unsupported families
		reject before publication instead of silently becoming negative predicates.
	 */
	public function renderRuntimePredicate():String {
		program.assertCurrent();
		final lines = [
			"inline bool hxhx_runtime_is_of_type(const hxhx::managed::Value& value, const hxhx::managed::Value& type) {",
			"  using hxhx::managed::ValueKind;",
			"  if (value.kind() == ValueKind::Null || type.kind() != ValueKind::Descriptor) return false;",
			"  const auto descriptor = type.asDescriptor();"
		];
		for (entry in descriptors) {
			if (entry.runtimeKind == null)
				continue;
			final condition = switch entry.runtimeKind {
				case ArrayCore:
					"value.kind() == ValueKind::Managed && value.asManaged().hasLayout<hxhx::managed::ArrayPayload>()";
				case StringCore:
					"value.kind() == ValueKind::String";
				case Nominal(_):
					final facts = entry.owner.requireSemanticFacts();
					if (facts.getIsExtern())
						throw "managed runtime predicate requires an explicit class family plan: " + facts.getClassIdentity();
					CppManagedNominalTypeTest.condition(program.getClassGraph(), facts.getClassIdentity(), [
						for (candidate in descriptors)
							if (candidate.layout != null) {identity: candidate.owner.requireSemanticFacts().getClassIdentity(), symbol: candidate.symbol}
					], "value");
				case _:
					throw "managed runtime predicate requires an explicit runtime category";
			};
			lines.push("  if (descriptor == &" + entry.symbol + ") return " + condition + ";");
		}
		lines.push('  throw std::invalid_argument("runtime predicate received a foreign class descriptor");');
		lines.push("}");
		return lines.join("\n");
	}
}
