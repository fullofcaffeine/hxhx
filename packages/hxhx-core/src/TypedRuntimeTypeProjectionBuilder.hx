/**
	Collects type-operation occurrences during one source-shaped body projection.

	This builder is local to projection construction. Sealing it returns an
	immutable catalog and prevents later expressions from joining that body.
**/
class TypedRuntimeTypeProjectionBuilder {
	final ownerIdentity:String;
	final bodyRevision:String;
	final entries:Array<TypedBackendRuntimeTypeOccurrence> = [];
	var sealed:Bool = false;

	public function new(ownerIdentity:String, bodyRevision:String) {
		this.ownerIdentity = ownerIdentity;
		this.bodyRevision = bodyRevision;
	}

	public function project(target:TypedRuntimeTypeTarget, ?value:HxExpr):HxExpr {
		if (sealed)
			throw "cannot add a runtime type operand to a sealed projection";
		final entry = new TypedBackendRuntimeTypeOccurrence(ownerIdentity, bodyRevision, target, value);
		entries.push(entry);
		return entry.getExpression();
	}

	/** Retain only occurrences present in the final projected body after lowering. */
	public function seal(markers:Array<HxExpr>):TypedBackendRuntimeTypeCatalog {
		if (sealed)
			throw "runtime type projection was sealed twice";
		sealed = true;
		final reachable = new Array<TypedBackendRuntimeTypeOccurrence>();
		for (marker in markers) {
			var selected:Null<TypedBackendRuntimeTypeOccurrence> = null;
			for (entry in entries)
				if (entry.getExpression() == marker) {
					selected = entry;
					break;
				}
			if (selected == null)
				throw "projected body contains a runtime type operand from another builder";
			reachable.push(selected);
		}
		return new TypedBackendRuntimeTypeCatalog(ownerIdentity, bodyRevision, reachable);
	}
}
