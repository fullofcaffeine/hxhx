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

	public function new() {}

	/** The emitter supplies its actual runtime-module selection, not a second name allowlist. */
	public function add(projection:TypedBackendClassProjection, runtimeProvided:Bool):Void {
		if (runtimeProvided)
			return;
		final facts = projection.requireSemanticFacts();
		if (facts.getIsExtern() || facts.getIsInterface() || !facts.getNominalKind().match(ClassInstance))
			return;
		final identity = facts.getClassIdentity();
		if (owners.exists(identity))
			throw "native class storage owner registered twice: " + identity;
		owners.set(identity, facts);
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
