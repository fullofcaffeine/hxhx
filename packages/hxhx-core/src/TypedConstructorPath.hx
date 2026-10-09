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
