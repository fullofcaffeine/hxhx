/**
	Find enum declarations required to represent a quoted syntax value.

	A quotation returns a checked record or enum type. Its closed enum alternatives
	and their payload types describe the runtime representation, independently of
	the names inside the quotation. Follow those signatures without retaining class
	methods, executing quoted code, or guessing providers from short names.

	Visit sealed alias templates and their arguments separately. This keeps the walk
	finite even when recursive applications grow their arguments on each expansion.
	The result is conservative across enum alternatives, not across whole modules.
 */
function find(type:TyType, providers:haxe.ds.StringMap<TypedClass>):Array<TypedClass> {
	final result = new Array<TypedClass>();
	final types = new haxe.ds.ObjectMap<TyType, Bool>();
	final aliases = new haxe.ds.ObjectMap<TyAliasDefinition, Bool>();
	final enums = new haxe.ds.ObjectMap<TypedClass, Bool>();
	function visit(current:TyType):Void {
		if (current == null || types.exists(current))
			return;
		types.set(current, true);
		final alias = current.getAliasDefinition();
		if (alias != null && !aliases.exists(alias)) {
			aliases.set(alias, true);
			visit(alias.getBody());
		}
		if (current.isNullable())
			visit(current.unwrapNull());
		for (child in current.getTypeArguments().concat(current.getFunctionArguments()).concat(current.getAnonymousFieldTypes()))
			visit(child);
		if (current.isFunction())
			visit(current.getFunctionReturn());
		final identity = current.getNominalIdentity();
		if (identity == null)
			return;
		final owner = providers.get(identity.getCanonicalName());
		if (owner == null)
			throw "quotation type has no exact program provider: " + identity.getCanonicalName();
		final info = owner.getSemanticInfo();
		if (info == null || !info.getIdentity().equals(identity))
			throw "quotation type provider disagrees with its exact identity";
		if (!info.getIsEnum() || enums.exists(owner))
			return;
		enums.set(owner, true);
		result.push(owner);
		for (declaration in info.getDeclarations())
			if (declaration.getIsEnumConstructor())
				for (argument in declaration.getSignature().getArgs())
					visit(argument);
	}
	visit(type);
	return result;
}
