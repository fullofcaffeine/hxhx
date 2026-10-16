package backend.ocaml;

/**
	Select field storage for ordinary generated classes in one native request.
	Only classes emitted by this request use HxAnon field storage. Externs, enums,
	abstracts, interfaces, and modules supplied by the native runtime remain under
	their existing representation owners. A declared field named length therefore
	remains an ordinary field without changing String, Array, or Bytes operations.
**/
class Stage3OcamlClassStorage {
	final owners:Map<String, TypedBackendClassSemanticFacts> = [];
	final projections:Map<String, TypedBackendClassProjection> = [];
	final modules:Map<String, String> = [];
	final initializers:Map<String, Stage3OcamlInstanceInitializers> = [];

	public function new() {}

	/** The emitter supplies its actual runtime-module selection, not a second name allowlist. */
	public function add(projection:TypedBackendClassProjection, runtimeProvided:Bool, ?outputModule:String):Void {
		if (runtimeProvided)
			return;
		final facts = projection.requireSemanticFacts();
		if (facts.getIsExtern() || facts.getIsInterface() || !facts.getNominalKind().match(ClassInstance))
			return;
		final identity = facts.getClassIdentity();
		if (owners.exists(identity))
			throw "native class storage owner registered twice: " + identity;
		final fields = new Array<TypedBackendFieldInitializerProjection>();
		for (declaration in HxClassDecl.getFields(projection.getDeclaration()))
			if (!HxFieldDecl.getIsStatic(declaration) && HxFieldDecl.getInit(declaration) != null) {
				final matches = projection.getFieldInitializers().filter(value -> value.getDeclaration() == declaration);
				if (matches.length != 1 || !facts.requireField(matches[0].getField()).hasStorage)
					throw "native instance initialization requires its exact stored field";
				fields.push(matches[0]);
			}
		final initializer = new Stage3OcamlInstanceInitializers({projection: projection, owner: identity, fields: fields});
		owners.set(identity, facts);
		projections.set(identity, projection);
		initializers.set(identity, initializer);
		if (outputModule != null)
			modules.set(identity, outputModule);
	}

	/** Return field execution only for the exact emitted class that owns it. */
	public function instanceInitializers(projection:TypedBackendClassProjection):Null<Stage3OcamlInstanceInitializers> {
		final plan = initializers.get(projection.requireSemanticFacts().getClassIdentity());
		if (plan != null)
			plan.assertOwner(projection);
		return plan != null && plan.hasFields() ? plan : null;
	}

	/** Retain child-to-parent forwarding, then initialize the selected constructor's own fields. */
	function initializerOwners(application:TypedConstructorApplication):Array<String> {
		return [
			for (type in application.getForwardedTypes().concat([application.getOwnerType()]))
				type.getNominalIdentity().getCanonicalName()
		];
	}

	/** Local dependency ordering must include generated field helpers used by an exact construction. */
	public function constructorDependencies(catalog:TypedBackendConstructorCatalog, currentModule:String):Array<String> {
		final result = new Array<String>();
		for (occurrence in catalog.getEntries()) {
			if (!ownsConstruction(occurrence))
				continue;
			final application = occurrence.requireApplication();
			if (modules.get(application.getDeclaration().getOwner().getCanonicalName()) == currentModule && result.indexOf("new") < 0)
				result.push("new");
			for (owner in initializerOwners(application)) {
				final plan = initializers.get(owner);
				if (plan != null && plan.hasFields() && modules.get(owner) == currentModule && result.indexOf(plan.getName()) < 0)
					result.push(plan.getName());
			}
		}
		return result;
	}

	/** Only a class emitted by this request may use ordinary object construction. */
	public function ownsConstruction(occurrence:TypedBackendConstructorOccurrence):Bool {
		occurrence.assertCurrent();
		final identity = occurrence.getConstructedType().getNominalIdentity();
		return identity != null && owners.exists(identity.getCanonicalName());
	}

	/** A checked spread passes its original array value, not the source-only spread marker. */
	public function argumentValues(occurrence:TypedBackendConstructorOccurrence):Array<HxExpr> {
		final arguments = occurrence.getArguments();
		final kinds = occurrence.requireArgumentBinding().getOperandKinds();
		return [
			for (index in 0...arguments.length)
				if (kinds[index] == Spread) switch arguments[index] {
					case ECall(EIdent("__hxhx_spread"), [value]):
						value;
					case _:
						throw "native constructor spread lost its original array operand";
				} else arguments[index]
		];
	}

	/**
		Invoke the exact selected constructor after evaluating each source operand once.
		Parent calls reuse this_ and never allocate another object. Field initialization
		remains owned by the declaration; argument positions do not define field values.
	 */
	public function construct(input:{
		occurrence:TypedBackendConstructorOccurrence,
		currentModule:String,
		names:Stage3OcamlLocalNames,
		emitArgument:(expression:HxExpr, actual:TyType, expected:TyType) -> String,
		quote:String->String
	}):Null<String> {
		final occurrence = input.occurrence;
		if (!ownsConstruction(occurrence))
			return null;
		if (input.names == null)
			throw "native construction requires its exact local naming owner";
		final application = occurrence.requireApplication();
		final declaration = application.getDeclaration();
		final owner = declaration.getOwner().getCanonicalName();
		final projection = projections.get(owner);
		final module = modules.get(owner);
		if (projection == null || module == null)
			throw "native constructor provider was not emitted: " + owner;
		final methods = projection.getFunctions().filter(fn -> fn.requireSemanticDeclaration() == declaration);
		if (methods.length != 1)
			throw "native constructor requires its exact declaration";
		final binding = occurrence.requireArgumentBinding();
		final slots = binding.getSlots();
		if (slots.length != methods[0].getParameters().length)
			throw "native constructor parameter projection changed its checked arity";
		final arguments = argumentValues(occurrence);
		final actual = binding.getOperandTypes();
		final expected = binding.getExpectedArguments();
		final locals = [
			for (index in 0...arguments.length)
				input.names.internalName("__hx_ctor_arg_" + index)
		];
		final rendered = [
			for (index in 0...arguments.length)
				input.emitArgument(arguments[index], actual[index], expected[index])
		];
		final parameters = [
			for (slot in slots)
				switch slot {
					case Supplied(index):
						locals[index];
					case Omitted:
						"(Obj.magic HxRuntime.hx_null)";
					case RestElements(indices):
						"HxBootArray.of_list [" + indices.map(index -> locals[index]).join("; ") + "]";
					case RestSpread(index):
						locals[index];
				}
		];
		final object = occurrence.getIsSuperCall() ? "this_" : input.names.internalName("__hx_obj");
		final callee = module == input.currentModule ? "new_" : module + ".new_";
		final call = callee + " (" + object + ")" + parameters.map(parameter -> " (" + parameter + ")").join("");
		var result = occurrence.getIsSuperCall() ? call : "ignore (" + call + "); " + object;
		final initialize = new Array<String>();
		for (owner in initializerOwners(application)) {
			final plan = initializers.get(owner);
			if (plan == null)
				throw "native construction lacks initializer owner: " + owner;
			if (plan.hasFields()) {
				final module = modules.get(owner);
				if (module == null)
					throw "native initializer provider was not emitted: " + owner;
				initialize.push((module == input.currentModule ? "" : module + ".") + plan.getName() + " (" + object + "); ");
			}
		}
		result = initialize.join("") + result;
		var index = arguments.length;
		while (index-- > 0)
			result = "let " + locals[index] + " = (" + rendered[index] + ") in " + result;
		if (!occurrence.getIsSuperCall()) {
			final fields = new Array<String>();
			var identity:Null<String> = occurrence.getConstructedType().getNominalIdentity().getCanonicalName();
			final visited:Map<String, Bool> = [];
			while (identity != null) {
				if (visited.exists(identity))
					throw "native construction has cyclic class storage";
				visited.set(identity, true);
				final facts = owners.get(identity);
				if (facts == null)
					throw "native construction lacks inherited storage: " + identity;
				for (field in facts.copyFields())
					if (!field.isStatic && field.hasStorage)
						fields.push("HxAnon.set (Obj.repr " + object + ") " + input.quote(field.name) + " HxRuntime.hx_null; ");
				identity = facts.getSuperClassIdentity();
			}
			result = "let " + object + " = HxAnon.create () in " + fields.join("") + result;
		}
		return "(" + result + ")";
	}

	/** Class values compare by identity; primitive and target-owned values keep their own rules. */
	public function usesIdentity(type:TyType):Bool {
		final value = TyAliasExpansion.revealNonNullable(type);
		final identity = value.getNominalIdentity();
		return value.isAnonymous() || value.isFunction() || (identity != null && owners.exists(identity.getCanonicalName()));
	}

	/** Read the selected declaration once, retaining the occurrence's applied result type. */
	public function read(occurrence:TypedBackendFieldOccurrence, emit:HxExpr->String, receiver:String, quote:String->String):Null<String> {
		final field = occurrence.getField();
		if (field.getIsStatic())
			return null;
		final facts = owners.get(field.getOwner().getCanonicalName());
		if (facts == null)
			return null;
		final selected = facts.requireField(field);
		if (!selected.hasStorage || (selected.propertyGet == "get" && !occurrence.getHasPropertyStorageAccess()))
			throw "native class field read requires lowered stored access: " + selected.canonicalIdentity;
		final object = switch occurrence.getExpression() {
			case EIdent(_) if (occurrence.getReceiver() == ImplicitOwner): receiver;
			case EField(value, _) if (occurrence.getReceiver() == ValueReceiver): emit(value);
			case _: throw "native instance field read lost its receiver";
		};
		return Stage3OcamlObjects.read(occurrence.getType(), "HxAnon.get (Obj.repr (" + object + ")) " + quote(selected.name));
	}
}
