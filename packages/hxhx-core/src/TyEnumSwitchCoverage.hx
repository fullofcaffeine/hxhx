/**
	Prove that structured cases cover every constructor of the exact input enum.

	A constructor counts only when all its payload patterns are irrefutable for
	the applied payload types. Guards and restricted payloads contribute no proof.
	This does not combine complementary payload patterns into a pattern matrix.
	The declaration index owns constructor identity; spellings alone cannot prove
	coverage for another enum with similarly named constructors.
 */
function proves(input:TyType, patterns:Array<HxSwitchPattern>, context:TyperContext, position:HxPos, isCapture:String->Bool):Bool {
	if (input == null || context == null || context.getIndex() == null || patterns == null)
		return false;
	var type = input;
	while (type.isNullable())
		type = type.unwrapNull();
	final identity = type.getNominalIdentity();
	final owner = identity == null ? null : context.getIndex().getByFullName(identity.getCanonicalName());
	if (owner == null || !owner.getIsEnum())
		return false;
	final constructors = owner.getEnumDeclaration().getConstructors();
	if (constructors.length == 0)
		return false;
	final covered = new haxe.ds.StringMap<Bool>();
	function constructor(name:String, children:Array<HxSwitchPattern>):Void {
		final dot = name.lastIndexOf('.');
		final member = dot < 0 ? name : name.substr(dot + 1);
		if (dot >= 0) {
			final qualifier = context.resolveType(name.substr(0, dot));
			if (qualifier == null || !qualifier.getIdentity().equals(identity))
				throw new TyperError(context.getFilePath(), position, 'Invalid enum pattern ' + name + ': constructor belongs to another enum');
		}
		final selected = constructors.filter(candidate -> candidate.name == member);
		if (selected.length != 1 || selected[0].arity != children.length)
			throw new TyperError(context.getFilePath(), position, 'Invalid enum pattern ' + name + ': constructor or payload arity differs');
		final arguments = children.length == 0 ? [] : TyEnumPatternArguments.resolve(type, name, children.length, context, position);
		if (arguments == null)
			return;
		for (index in 0...children.length)
			if (!TySwitchIrrefutable.proves(children[index], arguments[index], isCapture))
				return;
		// Names are keys only within this validated declaration's complete inventory.
		covered.set(member, true);
	}
	function collect(pattern:HxSwitchPattern):Void {
		switch pattern {
			case PEnumValue(name):
				constructor(name, []);
			case PEnumExtract(name, arguments):
				constructor(name, arguments == null ? [] : arguments);
			case POr(alternatives):
				if (alternatives != null)
					for (alternative in alternatives)
						collect(alternative);
			case PCapture(_, inner):
				collect(inner);
			case _:
		}
	}
	for (pattern in patterns)
		collect(pattern);
	for (declaration in constructors)
		if (!covered.exists(declaration.name))
			return false;
	return true;
}
