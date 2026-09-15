/**
	Exact nominal target selected by shared typing for a runtime type operation.

	The declaration identity is semantic data, not a display name to resolve again.
	Classes and interfaces share this target form; their assignability relation is
	owned by the shared class graph. Core and enum targets require explicit future
	admission rather than being disguised as nominal instances.
**/
class TypedRuntimeTypeTarget {
	final identity:TyNominalTypeId;
	final sourceSpelling:String;

	public function new(identity:TyNominalTypeId, ?sourceSpelling:String) {
		if (identity == null || identity.getCanonicalName().length == 0)
			throw "runtime type target requires an exact nominal identity";
		this.identity = identity;
		this.sourceSpelling = sourceSpelling == null || sourceSpelling.length == 0 ? identity.getCanonicalName() : sourceSpelling;
	}

	public function getIdentity():TyNominalTypeId
		return identity;

	/** Presentation only: preserve source qualifiers without using them to select a type. */
	public function getSourceSpelling():String
		return sourceSpelling;

	public function getInstanceType():TyType
		return TyType.nominal(identity, []);

	/** A class value has a meta-type, distinct from instances of the selected class. */
	public function getValueType():TyType
		return TyType.nominal(new TyNominalTypeId("Class"), [getInstanceType()]);

	public function getSemanticKey():String
		return "runtime-nominal:" + identity.getCanonicalName();
}
