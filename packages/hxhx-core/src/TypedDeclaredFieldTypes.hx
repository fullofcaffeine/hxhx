private typedef PublishedFieldType = {
	final declaration:TyFieldInfo;
	final source:HxFieldDecl;
	final fingerprint:String;
	final type:TyType;
};

/**
	Completed field types for one exact class header and source revision.
	The request-owned inference table supplies these results before backend
	projection. Headers stay immutable, so existing typed reads retain their
	declaration identity. Unknown cyclic results remain unknown.
 */
class TypedDeclaredFieldTypes {
	final owner:TyNominalInfo;
	final entries:Array<PublishedFieldType>;

	@:allow(TyFieldInitializerTypes)
	private function new(owner:TyNominalInfo, entries:Array<PublishedFieldType>) {
		this.owner = owner;
		this.entries = entries.copy();
	}

	public function assertOwner(expected:TyNominalInfo):Void {
		if (owner != expected)
			throw "published field types belong to another class header";
		assertCurrent();
	}

	/** Source mutation invalidates publication even when the inferred type is unchanged. */
	public function assertCurrent():Void {
		for (entry in entries) {
			final initializer = HxFieldDecl.getInit(entry.source);
			if (initializer == null || TypedBodyFingerprint.exactExpression(initializer) != entry.fingerprint)
				throw "published field type belongs to changed initializer source";
		}
	}

	public function typeFor(field:TyFieldInfo):TyType {
		assertCurrent();
		if (owner.fieldInfo(field.getName()) != field)
			throw "published field type requires its exact declaration";
		for (entry in entries)
			if (entry.declaration == field)
				return entry.type;
		return field.getType();
	}
}
