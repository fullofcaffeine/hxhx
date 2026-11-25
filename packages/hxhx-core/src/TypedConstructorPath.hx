/**
	The allocated type and its nearest declared constructor owner. Each forwarded
	type lacks an own constructor and keeps its applied superclass arguments.
	These types later authorize initializer execution; they are not callable bodies.
	Only checked index traversal can create this proof. An inapplicable nearest
	constructor never causes traversal to continue to a more distant ancestor.
 */
class TypedConstructorPath {
	final constructed:TyType;
	final owner:TyNominalInfo;
	final ownerType:TyType;
	final forwarded:Array<TyType>;

	private function new(constructed:TyType, owner:TyNominalInfo, ownerType:TyType, forwarded:Array<TyType>) {
		this.constructed = constructed;
		this.owner = owner;
		this.ownerType = ownerType;
		this.forwarded = forwarded.copy();
	}

	/** Missing declarations and inheritance cycles cannot manufacture a default constructor. */
	public static function select(index:TyperIndex, constructed:TyType):Null<TypedConstructorPath> {
		if (index == null || constructed == null)
			return null;
		var selected = constructed;
		final visited = new haxe.ds.StringMap<Bool>();
		final forwarded = new Array<TyType>();
		while (selected.getNominalIdentity() != null) {
			final identity = selected.getNominalIdentity().getCanonicalName();
			if (visited.exists(identity))
				return null;
			visited.set(identity, true);
			final owner = index.getByFullName(identity);
			if (owner == null)
				return null;
			// The nominal index stores classes and abstracts together. Narrow only
			// after validating the kind; only ordinary class edges can be inherited.
			final cls:Null<TyClassInfo> = Std.isOfType(owner, TyClassInfo) ? (cast owner : TyClassInfo) : null;
			final parameters = if (cls != null && !cls.getIsInterface() && !cls.getIsEnum()) {
				cls.getTypeParameterIds();
			} else if (forwarded.length == 0 && Std.isOfType(owner, TyAbstractInfo)) {
				(cast owner : TyAbstractInfo).getTypeParameterIds();
			} else return null;
			if (parameters.length != selected.getTypeArguments().length)
				return null;
			if (owner.instanceMethodCandidates("new").length != 0)
				return new TypedConstructorPath(constructed, owner, selected, forwarded);
			if (cls == null || cls.getSuperType() == null)
				return null;
			final bindings = TyTypeSubstitution.bind(parameters, selected.getTypeArguments(), identity);
			forwarded.push(selected);
			selected = TyTypeSubstitution.apply(cls.getSuperType(), bindings);
		}
		return null;
	}

	/**
		The constructor that a class without its own `new` inherits, as upstream Haxe 4.3.7 gives
		such a non-extern class one (`typeloadFunction.ml`, `add_constructor`, lines 183-240): the
		nearest ancestor's `new`, applied through this class's view of that ancestor, with a Void
		result. `class C<T> extends P<Array<T>>` inherits `P`'s `new(items:S)` as
		`new(items:Array<T>)`. Null for an extern class, an interface, an enum, an abstract, a class
		that declares `new`, a class without an inherited constructor, and an overloaded one.

		This is a derived view for typed-signature tools such as the typed oracle. The index and the
		typed classes keep only declared functions, so constructor selection
		(`select`) and every backend are unchanged. `declaration` is the ancestor's `new`.
	**/
	public static function inheritedSignature(index:TyperIndex, info:Null<TyNominalInfo>):Null<{declaration:TyDeclarationInfo, signature:TyFunSig}> {
		if (index == null || info == null || !Std.isOfType(info, TyClassInfo))
			return null;
		final cls:TyClassInfo = cast info;
		if (cls.getIsInterface() || cls.getIsEnum() || cls.getIsExtern() || cls.instanceMethodCandidates("new").length != 0)
			return null;
		final path = select(index, TyType.nominal(cls.getIdentity(), [for (parameter in cls.getTypeParameterIds()) TyType.typeParameter(parameter)]));
		if (path == null || path.getOwner() == info)
			return null;
		final candidates = path.getOwner().instanceMethodCandidates("new");
		final declaration = candidates.length == 1 ? path.getOwner().declarationForSignature(candidates[0]) : null;
		if (declaration == null)
			return null;
		final applied = TyNominalApplication.signature(index, path.getOwner(), path.getOwnerType(), candidates[0]);
		return {
			declaration: declaration,
			signature: new TyFunSig("new", false, applied.getArgNames(), applied.getArgs(), applied.getArgOptional(), applied.getArgRest(),
				TyType.fromHintText("Void"), applied.getPos())
		};
	}

	public function getOwner():TyNominalInfo
		return owner;

	public function getOwnerType():TyType
		return ownerType;

	/** The order is allocated child first, ending immediately before the explicit constructor owner. */
	public function getForwardedTypes():Array<TyType>
		return forwarded.copy();

	public function assertOwner(selected:TyNominalInfo, result:TyType):Void {
		if (selected != owner || result == null || result.getSemanticKey() != constructed.getSemanticKey())
			throw "constructor path belongs to another owner or allocated result";
	}
}
