/**
	Immutable runtime type occurrences for one exact function or field initializer.

	Lookup uses projected object identity, never a name or structural equality.
	A second projection of identical source owns different occurrences. Callers
	must select the executable projection before asking it for an operand.
**/
class TypedBackendRuntimeTypeCatalog {
	final ownerIdentity:String;
	final bodyRevision:String;
	final entries:Array<TypedBackendRuntimeTypeOccurrence>;

	public function new(ownerIdentity:String, bodyRevision:String, entries:Array<TypedBackendRuntimeTypeOccurrence>) {
		if (ownerIdentity == null || ownerIdentity.length == 0 || bodyRevision == null || bodyRevision.length == 0)
			throw "runtime type catalog requires an exact executable revision";
		this.ownerIdentity = ownerIdentity;
		this.bodyRevision = bodyRevision;
		this.entries = entries == null ? [] : entries.copy();
		for (index in 0...this.entries.length) {
			final entry = this.entries[index];
			if (entry == null)
				throw "runtime type catalog contains a missing occurrence";
			entry.assertOwner(ownerIdentity, bodyRevision);
			entry.assertCurrent();
			for (previous in 0...index)
				if (this.entries[previous].getExpression() == entry.getExpression())
					throw "runtime type catalog contains a repeated occurrence";
		}
	}

	public function getEntries():Array<TypedBackendRuntimeTypeOccurrence>
		return entries.copy();

	public function assertOwner(owner:String, revision:String):Void {
		if (ownerIdentity != owner || bodyRevision != revision)
			throw "runtime type catalog belongs to another executable or revision";
	}

	/** The catalog must account for every marker in the actual projected body. */
	public function assertMarkers(markers:Array<HxExpr>):Void {
		if (markers.length != entries.length)
			throw "runtime type catalog does not match the projected body";
		for (index in 0...markers.length) {
			require(markers[index], ownerIdentity, bodyRevision);
			for (previous in 0...index)
				if (markers[previous] == markers[index])
					throw "projected body repeats one runtime type occurrence";
		}
	}

	public function require(expression:HxExpr, owner:String, revision:String):TypedBackendRuntimeTypeOccurrence {
		assertOwner(owner, revision);
		for (entry in entries)
			if (entry.getExpression() == expression) {
				entry.assertCurrent();
				return entry;
			}
		throw "runtime type operand is not an exact occurrence in this executable projection";
	}

	/** Admission check for a consumer that has no implementation for this fact yet. */
	public function assertUnsupportedAbsent(consumer:String):Void {
		if (entries.length > 0)
			throw consumer + " does not support runtime type operands in " + ownerIdentity;
	}
}
