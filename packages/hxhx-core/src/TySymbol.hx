/**
	Mutable inference symbol for one function-local declaration.

	The stable identity and declaration kind never change. Typing may refine the
	semantic type while the function is being built; the typed-body boundary then
	snapshots the symbol as an immutable `TyLocalBinding`.
**/
class TySymbol {
	public final name:String;

	final identity:TyLocalId;
	final kind:TyLocalDeclarationKind;
	var ty:TyType;
	var staticsOwner:Null<TyNominalInfo> = null;

	public function new(name:String, ty:TyType, identity:TyLocalId, kind:TyLocalDeclarationKind) {
		if (identity == null)
			throw "typed local symbol requires a stable identity";
		this.name = name == null ? "" : name;
		this.ty = ty == null ? TyType.unknown() : ty;
		this.identity = identity;
		this.kind = kind;
	}

	public function getName():String
		return name;

	public function getType():TyType
		return ty;

	public function getIdentity():TyLocalId
		return identity;

	public function getKind():TyLocalDeclarationKind
		return kind;

	/** Freeze the current inferred type for storage on a structural typed node. **/
	public function toBinding():TyLocalBinding
		return new TyLocalBinding(identity, name, ty, kind);

	/**
		Refine a symbol's type during typing.

		Why
		- Stage 3 starts with partial information: a `var x = expr;` has no
		  explicit type hint, but we can infer a type from the initializer.
		- For bootstrapping, we prefer “refine in place” so all subsequent lookups
		  of `x` see the improved type.

		How
		- This is intentionally tiny and unsafe compared to upstream Haxe’s
		  monomorph/unification engine.
		- Callers must keep updates deterministic: only refine from `Unknown` or
		  from compatible types.
	**/
	public function setType(t:TyType):Void {
		this.ty = t;
	}

	/**
		The class whose statics this local holds: `var s = Something;` without a written type.
		Haxe 4.3.7 types such a local as the class's statics, so `s.f()` is a static access of
		`Something`; a written `Class<Something>` is not (upstream rejects its static fields).
		Typing marks it once; sealed replay reuses this same symbol.
	**/
	public function getStaticsOwner():Null<TyNominalInfo>
		return staticsOwner;

	public function markStaticsOwner(owner:TyNominalInfo):Void {
		staticsOwner = owner;
	}
}
