/**
	One immutable, target-neutral result of resolving a module directive.

	The parsed directive is retained for source spelling, macro inspection, and
	diagnostics. `providers` contains every exact Haxe type selected by the
	directive. A plain module import or module-level `using` can select several
	types, while an aliased type, static member, or static wildcard selects exactly
	one. Package wildcards and unresolved inputs deliberately have no provider.
**/
class TyModuleDirective {
	final source:HxModuleDirective;
	final kind:TyModuleDirectiveKind;
	final providers:Array<TyNominalTypeId>;

	public function new(source:HxModuleDirective, kind:TyModuleDirectiveKind, ?providers:Array<TyNominalTypeId>) {
		if (source == null)
			throw "typed module directive requires its parsed source";
		if (kind == null)
			throw "typed module directive requires a resolved kind";
		final selected = providers == null ? [] : providers.copy();
		for (provider in selected)
			if (provider == null)
				throw "typed module directive cannot contain a missing provider";
		final providerCountIsValid = if (kind.match(TypeImport) || kind.match(UsingType)) {
			selected.length > 0;
		} else if (kind.match(StaticMemberImport(_)) || kind.match(StaticWildcardImport)) {
			selected.length == 1;
		} else {
			selected.length == 0;
		};
		if (!providerCountIsValid)
			throw "typed module directive provider count does not match its resolved kind";
		this.source = source;
		this.kind = kind;
		this.providers = selected;
	}

	public function getSource():HxModuleDirective
		return source;

	public function getKind():TyModuleDirectiveKind
		return kind;

	/** Return a copy of every exact type selected by this directive. **/
	public function getProviders():Array<TyNominalTypeId>
		return providers.copy();

	/** Return the provider for directive kinds whose contract requires exactly one. **/
	public function getSingleProvider():Null<TyNominalTypeId>
		return providers.length == 1 ? providers[0] : null;

	/**
		Return the local type name introduced for one selected provider.

		An alias renames its single provider. A plain module import keeps each
		provider's declared short name, including secondary types from the module.
	**/
	public function getImportedTypeLocalName(provider:TyNominalTypeId):Null<String> {
		if (!kind.match(TypeImport) || provider == null)
			return null;
		var selected = false;
		for (candidate in providers)
			if (candidate.equals(provider)) {
				selected = true;
				break;
			}
		if (!selected)
			return null;
		return switch (HxModuleDirective.getKind(source)) {
			case ImportAlias(alias): alias;
			case ImportNormal:
				final canonical = provider.getCanonicalName();
				final dot = canonical.lastIndexOf(".");
				dot < 0 ? canonical : canonical.substr(dot + 1);
			case ImportAll | Using: null;
		};
	}

	/** The local name introduced for an exact static-member import. **/
	public function getStaticLocalName():Null<String> {
		return switch (kind) {
			case StaticMemberImport(_): HxModuleDirective.getImportedLocalName(source);
			case _: null;
		};
	}

	/** Stable representation for typed-module revision and focused diagnostics. **/
	public function canonicalIdentity():String {
		final providerNames = [for (provider in providers) provider.getCanonicalName()];
		final providerSet = providerNames.join(",");
		final resolved = switch (kind) {
			case TypeImport: "types:" + providerSet;
			case StaticMemberImport(memberName): "static-member:" + providerSet + ":" + memberName;
			case StaticWildcardImport: "static-all:" + providerSet;
			case PackageWildcardImport: "package-all:" + HxModuleDirective.getPath(source);
			case UsingType: "using-types:" + providerSet;
			case Unresolved: "unresolved";
		};
		return HxModuleDirective.canonicalIdentity(source) + "=>" + resolved;
	}
}
