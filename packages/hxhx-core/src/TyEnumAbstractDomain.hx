/** Exact enum member and source position, retained in declaration order. */
typedef TyEnumAbstractMember = {
	final field:TyFieldInfo;
	final position:HxPos;
};

/**
	The declared finite domain of an enum abstract before target representation erases it.
	Member identity stays distinct from constant equality: two declarations can cover
	the same value, while diagnostics use the first declared name for that value.
**/
class TyEnumAbstractDomain {
	final owner:TyNominalTypeId;
	final members:Array<TyEnumAbstractMember>;

	public function new(owner:TyNominalTypeId, members:Array<TyEnumAbstractMember>) {
		this.owner = owner;
		this.members = members.copy();
		for (member in members)
			if (!member.field.getOwner().equals(owner) || !member.field.getConstant().isEnumValue())
				throw "enum-abstract domain requires exact constant members of its owner";
	}

	public function getOwner():TyNominalTypeId
		return owner;

	public function getMembers():Array<TyEnumAbstractMember>
		return members.copy();
}
