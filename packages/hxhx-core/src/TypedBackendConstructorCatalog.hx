/**
	Applied constructions belonging to one function or field initializer revision.

	An expression is identified by its projected object, not by its path, printed
	syntax, or traversal position. A second projection of the same source gets its
	own occurrences. Backend consumers must first select the owning projection.
 */
class TypedBackendConstructorCatalog {
	final ownerIdentity:String;
	final bodyRevision:String;
	final entries:Array<TypedBackendConstructorOccurrence>;

	public function new(ownerIdentity:String, bodyRevision:String, entries:Array<TypedBackendConstructorOccurrence>) {
		if (ownerIdentity == null
			|| ownerIdentity.length == 0
			|| bodyRevision == null
			|| bodyRevision.length == 0
			|| entries == null)
			throw "constructor catalog requires an exact executable revision and occurrences";
		this.ownerIdentity = ownerIdentity;
		this.bodyRevision = bodyRevision;
		this.entries = entries.copy();
		for (index in 0...entries.length) {
			final entry = entries[index];
			if (entry == null)
				throw "constructor catalog contains a missing occurrence";
			entry.assertOwner(ownerIdentity, bodyRevision);
			entry.assertCurrent();
			for (previous in 0...index)
				if (entries[previous].getExpression() == entry.getExpression())
					throw "constructor catalog contains a repeated occurrence";
		}
	}

	public function getEntries():Array<TypedBackendConstructorOccurrence>
		return entries.copy();

	public function assertOwner(owner:String, revision:String):Void {
		if (ownerIdentity != owner || bodyRevision != revision)
			throw "constructor catalog belongs to another executable or revision";
	}

	public function require(expression:HxExpr, owner:String, revision:String):TypedBackendConstructorOccurrence {
		assertOwner(owner, revision);
		final entry = find(expression);
		if (entry == null)
			throw "constructor is not an exact occurrence in this executable projection";
		return entry;
	}

	function find(expression:HxExpr):Null<TypedBackendConstructorOccurrence> {
		for (entry in entries)
			if (entry.getExpression() == expression) {
				entry.assertCurrent();
				return entry;
			}
		return null;
	}

	/** Every executable new expression must have exactly one occurrence, including unresolved selections. */
	public function assertExpressions(expressions:Array<HxExpr>):Void {
		if (expressions.length != entries.length)
			throw "constructor catalog does not match the projected body";
		for (index in 0...expressions.length) {
			require(expressions[index], ownerIdentity, bodyRevision);
			for (previous in 0...index)
				if (expressions[previous] == expressions[index])
					throw "projected body repeats one constructor occurrence";
		}
	}
}
