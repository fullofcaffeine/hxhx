import haxe.ds.StringMap;

/**
	Immutable function-local mapping between typed bindings and source-shaped
	backend transport names.

	The catalog sorts exact binding identities before assigning compact names.
	This keeps projection deterministic without encoding semantic facts in a
	magic identifier. Duplicate identities with different semantic types fail
	before any backend can emit ambiguous output.
**/
class TypedBackendLocalCatalog {
	final entries:Array<TypedBackendLocalProjection>;
	final byIdentity:StringMap<TypedBackendLocalProjection>;
	final byProjectedName:StringMap<TypedBackendLocalProjection>;
	final catchUses:StringMap<TypedCatchUse>;

	public function new(bindings:Array<TyLocalBinding>, ?reservedProjectedNames:Array<String>, ?catchUses:Array<TypedCatchUse>) {
		final exactBindings = new StringMap<TyLocalBinding>();
		final identities = new Array<String>();
		final sourceNames = new StringMap<Bool>();
		final reservedNames = new StringMap<Bool>();
		if (reservedProjectedNames != null)
			for (name in reservedProjectedNames) {
				if (name == null || name.length == 0)
					throw "typed backend local catalog cannot reserve an empty transport name";
				reservedNames.set(name, true);
			}
		if (bindings != null)
			for (binding in bindings) {
				if (binding == null)
					throw "typed backend local catalog cannot contain a null binding";
				final identity = binding.getIdentity().getCanonicalKey();
				final sourceName = binding.getSourceName().length == 0 ? "local" : binding.getSourceName();
				sourceNames.set(sourceName, true);
				final existing = exactBindings.get(identity);
				if (existing == null) {
					exactBindings.set(identity, binding);
					identities.push(identity);
				} else if (existing.getCanonicalIdentity() != binding.getCanonicalIdentity()) {
					throw "conflicting typed local facts for " + identity;
				}
			}
		identities.sort((left, right) -> Reflect.compare(left, right));

		this.entries = [];
		this.byIdentity = new StringMap<TypedBackendLocalProjection>();
		this.byProjectedName = new StringMap<TypedBackendLocalProjection>();
		this.catchUses = new StringMap<TypedCatchUse>();
		for (index in 0...identities.length) {
			final binding = exactBindings.get(identities[index]);
			if (binding == null)
				throw "typed backend local catalog lost a normalized binding";
			final sourceName = binding.getSourceName().length == 0 ? "local" : binding.getSourceName();
			var projectedName = sourceName;
			var suffix = 0;
			while (byProjectedName.exists(projectedName)
				|| reservedNames.exists(projectedName)
				|| (suffix > 0 && sourceNames.exists(projectedName))) {
				suffix++;
				projectedName = sourceName + "_" + suffix;
			}
			final entry = new TypedBackendLocalProjection(projectedName, binding);
			entries.push(entry);
			byIdentity.set(identities[index], entry);
			byProjectedName.set(projectedName, entry);
		}
		if (catchUses != null)
			for (use in catchUses) {
				if (use == null)
					throw "typed backend local catalog received a null catch use";
				final identity = use.binding.getIdentity().getCanonicalKey();
				final local = byIdentity.get(identity);
				if (local == null
					|| !local.getBinding().getKind().match(CatchVariable)
					|| local.getBinding().getCanonicalIdentity() != use.binding.getCanonicalIdentity())
					throw "typed backend catch use belongs to another local catalog";
				if (this.catchUses.exists(identity))
					throw "typed backend local catalog received duplicate catch uses";
				this.catchUses.set(identity, use);
			}
	}

	public function getEntries():Array<TypedBackendLocalProjection>
		return entries.copy();

	public function projectedName(binding:TyLocalBinding):String {
		if (binding == null)
			throw "typed backend projection requested a null local binding";
		final identity = binding.getIdentity().getCanonicalKey();
		final entry = byIdentity.get(identity);
		if (entry == null)
			throw "typed backend projection is missing local binding " + identity;
		if (entry.getBinding().getCanonicalIdentity() != binding.getCanonicalIdentity())
			throw "typed backend projection received stale local facts for " + identity;
		return entry.getProjectedName();
	}

	public function findByProjectedName(projectedName:String):Null<TypedBackendLocalProjection>
		return projectedName == null ? null : byProjectedName.get(projectedName);

	public function findByIdentity(bindingIdentity:String):Null<TypedBackendLocalProjection>
		return bindingIdentity == null ? null : byIdentity.get(bindingIdentity);

	/** Retrieve implicit provider facts by exact binding identity, never by source spelling. */
	public function findCatchUse(bindingIdentity:String):Null<TypedCatchUse>
		return bindingIdentity == null ? null : catchUses.get(bindingIdentity);
}
