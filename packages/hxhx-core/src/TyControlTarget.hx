/** A source traversal owner or a destination for an abrupt transfer of control. */
enum TyControlTargetKind {
	/** An expression owner that cannot receive return, break, or continue. */
	Initializer;

	Function;
	Loop;
}

/** Construction facts for a target in one owning source traversal. */
typedef TyControlTargetInput = {
	final ownerIdentity:String;
	final sourceRevision:String;
	final ordinal:Int;
	final kind:TyControlTargetKind;
	final sourceIdentity:String;
	final ?parent:TyControlTarget;
}

/**
	Identifies an initializer, function, or loop in an exact source revision.

	A return inside a value block keeps the enclosing function target. Lowering
	must preserve this identity when it introduces temporaries or helper functions.
	Source-order ordinals distinguish nested targets without using generated names.
 */
class TyControlTarget {
	final ownerIdentity:String;
	final sourceRevision:String;
	final ordinal:Int;
	final kind:TyControlTargetKind;
	final sourceIdentity:String;
	final parent:Null<TyControlTarget>;

	public function new(input:TyControlTargetInput) {
		if (input.ownerIdentity.length == 0
			|| input.sourceRevision.length == 0
			|| input.sourceIdentity.length == 0
			|| input.ordinal < 0)
			throw "control target requires an owner, source revision, and source identity";
		this.ownerIdentity = input.ownerIdentity;
		this.sourceRevision = input.sourceRevision;
		this.ordinal = input.ordinal;
		this.kind = input.kind;
		this.sourceIdentity = input.sourceIdentity;
		this.parent = input.parent;
		if (parent != null
			&& (parent.ownerIdentity != ownerIdentity || parent.sourceRevision != sourceRevision || parent.ordinal >= ordinal))
			throw "control target parent belongs to another source traversal";
	}

	public function getKind():TyControlTargetKind
		return kind;

	public function getSourceIdentity():String
		return sourceIdentity;

	public function getOwnerIdentity():String
		return ownerIdentity;

	public function getParent():Null<TyControlTarget>
		return parent;

	public function getCanonicalIdentity():String {
		return CompilerCacheIdentity.encode([
			"control-target-v1",
			ownerIdentity,
			sourceRevision,
			Std.string(ordinal),
			switch kind {
				case Initializer:
					"initializer";
				case Function:
					"function";
				case Loop:
					"loop";
			},
			sourceIdentity,
			parent == null ? null : Std.string(parent.ordinal)
		]);
	}
}
