import TySwitchAnalysis.TySwitchCaseCoverage;

/**
	Resolve patterns against the exact scrutinee declaration before coverage analysis.
	Other switch families remain with their existing typer. Applicable unsupported
	patterns fail explicitly instead of claiming that the switch is exhaustive.
**/
function check(scrutinee:TyType, patterns:Array<HxSwitchPattern>, bodyCount:Int, ctx:TyperContext, pos:HxPos):Void {
	if (patterns == null || patterns.length != bodyCount)
		throw new TyperError(ctx.getFilePath(), pos, "switch pattern/body count differs");
	final identity = scrutinee.getNominalIdentity();
	if (identity == null || ctx.getIndex() == null)
		return;
	final info = ctx.getIndex().getAbstractByFullName(identity.getCanonicalName());
	if (info == null || info.getEnumDomain() == null)
		return;
	final domain = info.getEnumDomain();

	function resolveMember(name:String):Null<TyFieldInfo> {
		final dot = name.lastIndexOf(".");
		if (dot >= 0) {
			final owner = ctx.resolveType(name.substr(0, dot));
			return owner == null ? null : owner.fieldInfo(name.substr(dot + 1));
		}
		final own = info.fieldInfo(name);
		return own != null ? own : ctx.importedStaticField(name);
	}
	function resolve(pattern:HxSwitchPattern):TySwitchCaseCoverage {
		return switch (pattern) {
			case PWildcard: CatchAll;
			case PBind(name):
				final field = resolveMember(name);
				field == null ? CatchAll : Member(field);
			case PEnumValue(name):
				final field = resolveMember(name);
				field == null ? Unsupported("unresolved enum pattern " + name) : Member(field);
			case POr(items): Alternatives([for (item in items) resolve(item)]);
			case PCapture(_, inner): resolve(inner);
			case PLengthGuard(inner, _, _) | PStartsWithGuard(inner, _, _) | PIntEqualsGuard(inner, _, _) | PIntCompareGuard(inner, _, _, _) |
				PParsedIntSwitchGuard(inner, _, _, _) | PUnsupportedGuard(inner): Guarded(resolve(inner));
			case _: Unsupported("pattern form requires enum-abstract coverage support");
		};
	}
	final result = new TySwitchAnalysis(domain).analyze([for (pattern in patterns) resolve(pattern)]);
	switch (result) {
		case Exhaustive:
		case NonExhaustive(missing):
			final names = [for (member in missing) member.getName()];
			names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
			throw new TyperError(ctx.getFilePath(), pos, "Unmatched patterns: " + names.join(" | "));
		case Indeterminate(reason):
			throw new TyperError(ctx.getFilePath(), pos, "Cannot analyze enum-abstract switch: " + reason);
	}
}
