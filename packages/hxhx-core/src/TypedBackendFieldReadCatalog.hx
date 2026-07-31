import haxe.ds.StringMap;

/**
	Immutable function-owned catalog of exact bare field reads.

	Only fields actually selected by typed expressions enter the catalog. A
	transport name may repeat for the same declaration, but conflicting owners,
	types, or declaration facts fail before rendering can guess which field a
	bare identifier represents.
**/
class TypedBackendFieldReadCatalog {
	final entries:Array<TypedBackendFieldReadProjection>;
	final byProjectedName:StringMap<TypedBackendFieldReadProjection>;

	public function new(reads:Array<TypedBackendFieldReadProjection>) {
		final exactReads = new StringMap<TypedBackendFieldReadProjection>();
		final names = new Array<String>();
		if (reads != null)
			for (read in reads) {
				if (read == null)
					throw "typed backend field-read catalog cannot contain a null projection";
				final name = read.getProjectedName();
				final existing = exactReads.get(name);
				if (existing == null) {
					exactReads.set(name, read);
					names.push(name);
				} else if (existing.getCanonicalIdentity() != read.getCanonicalIdentity()) {
					throw "conflicting typed field-read facts for transport name " + name;
				}
			}
		names.sort((left, right) -> Reflect.compare(left, right));

		this.entries = [];
		this.byProjectedName = new StringMap<TypedBackendFieldReadProjection>();
		for (name in names) {
			final read = exactReads.get(name);
			if (read == null)
				throw "typed backend field-read catalog lost a normalized projection";
			entries.push(read);
			byProjectedName.set(name, read);
		}
	}

	public function getEntries():Array<TypedBackendFieldReadProjection>
		return entries.copy();

	/** Names that local projection must not reuse inside this function body. **/
	public function getReservedProjectedNames():Array<String>
		return [for (entry in entries) entry.getProjectedName()];

	public function findByProjectedName(projectedName:String):Null<TypedBackendFieldReadProjection>
		return projectedName == null ? null : byProjectedName.get(projectedName);
}
