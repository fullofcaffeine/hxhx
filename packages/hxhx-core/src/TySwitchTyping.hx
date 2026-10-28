import TySwitchAnalysis.TySwitchCaseCoverage;
import TySwitchAnalysis.TySwitchCoverageResult;

/**
	Resolve patterns against the exact scrutinee declaration before coverage analysis.
	Other switch families remain with their existing typer. Applicable unsupported
	patterns fail explicitly instead of claiming that the switch is exhaustive.
**/
function check(scrutinee:TyType, patterns:Array<HxSwitchPattern>, bodyCount:Int, ctx:TyperContext, pos:HxPos):Void {
	if (patterns == null || patterns.length != bodyCount)
		throw new TyperError(ctx.getFilePath(), pos, "switch pattern/body count differs");
	final result = analyze(scrutinee, patterns, ctx, false);
	if (result == null)
		return;
	switch (result) {
		case Exhaustive:
		case NonExhaustiveWildcard:
			throw new TyperError(ctx.getFilePath(), pos, "Unmatched patterns: _");
		case NonExhaustive(missing):
			final names = [for (member in missing) member.getName()];
			names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
			throw new TyperError(ctx.getFilePath(), pos, "Unmatched patterns: " + names.join(" | "));
		case Indeterminate(reason):
			throw new TyperError(ctx.getFilePath(), pos, "Cannot analyze enum-abstract switch: " + reason);
	}
}

/** Publish complete declared-value and null coverage; diagnostic permission to omit null does not initialize a result. */
function provesValueCoverage(scrutinee:TyType, patterns:Array<HxSwitchPattern>, ctx:TyperContext):Bool {
	final identity = scrutinee.getNominalIdentity();
	final owner = identity == null || ctx.getIndex() == null ? null : ctx.getIndex().getAbstractByFullName(identity.getCanonicalName());
	if (owner == null || owner.getImplicitFromTypes().length != 0)
		return false;
	// Constructors and declared input conversions can create backing values
	// outside the constant domain. Diagnostics alone cannot prove those paths.
	for (declaration in owner.getDeclarations())
		if (declaration.getSignature().getName() == "new" || declaration.getMetadata().indexOf("from") >= 0)
			return false;
	final result = analyze(scrutinee, patterns, ctx, admitsNull(owner.getUnderlyingType()));
	return result != null && result.match(Exhaustive);
}

/**
	Only a nullable representation can reach a value switch as null. An exact
	Int, Float, or Bool backing (for example std `XmlType(Int)`) holds no null
	on static targets, so its declared members alone cover the input; a
	String or object backing still needs an explicit null arm. A `Null<...>`
	scrutinee is not an exact abstract application and never reaches this proof.
 */
private function admitsNull(underlying:TyType):Bool {
	if (underlying.isNullable() || !underlying.isPrimitive())
		return true;
	return !(underlying.isNumeric() || underlying.getDisplay() == "Bool");
}

/** Both consumers resolve the same exact field declarations and constant identities. */
private function analyze(scrutinee:TyType, patterns:Array<HxSwitchPattern>, ctx:TyperContext, requireNullCoverage:Bool):Null<TySwitchCoverageResult> {
	final identity = scrutinee.getNominalIdentity();
	if (identity == null || ctx.getIndex() == null || patterns == null)
		return null;
	final info = ctx.getIndex().getAbstractByFullName(identity.getCanonicalName());
	if (info == null || info.getEnumDomain() == null)
		return null;
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
			case PNull: NullOnly;
			case PWildcard: CatchAll;
			case PBind(name):
				final field = resolveMember(name);
				field == null ? CatchAll : Member(field);
			case PEnumValue(name):
				final field = resolveMember(name);
				field == null ? Unsupported("unresolved enum pattern " + name) : Member(field);
			case POr(items): Alternatives([for (item in items) resolve(item)]);
			case PCapture(_, inner): resolve(inner);
			case PGuard(inner, _) | PUnsupportedPattern(inner): Guarded(resolve(inner));
			case _: Unsupported("pattern form requires enum-abstract coverage support");
		};
	}
	return new TySwitchAnalysis(domain).analyze([for (pattern in patterns) resolve(pattern)], requireNullCoverage);
}
