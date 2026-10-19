import haxe.ds.StringMap;

/** Resolved coverage evidence; a guard never proves that a value is covered. */
enum TySwitchCaseCoverage {
	Member(field:TyFieldInfo);
	CatchAll;
	NullOnly;
	Guarded(pattern:TySwitchCaseCoverage);
	Alternatives(cases:Array<TySwitchCaseCoverage>);
	Unsupported(reason:String);
}

/** Explicit results prevent an unsupported pattern from masquerading as complete coverage. */
enum TySwitchCoverageResult {
	Exhaustive;
	NonExhaustive(missing:Array<TyFieldInfo>);
	NonExhaustiveWildcard;
	Indeterminate(reason:String);
}

/**
	Checks a resolved finite domain without reading source spellings or target output.
	Equal typed backing constants share coverage. Missing witnesses retain their exact
	declarations; presentation order belongs to the diagnostic caller.
**/
class TySwitchAnalysis {
	final domain:TyEnumAbstractDomain;

	public function new(domain:TyEnumAbstractDomain) {
		this.domain = domain;
	}

	/** Value-result lowering also requires null coverage, including null without a named member. */
	public function analyze(cases:Array<TySwitchCaseCoverage>, requireNullCoverage:Bool = false):TySwitchCoverageResult {
		final covered = new StringMap<Bool>();
		var catchAll = false;
		var hasMemberPattern = false;
		var unsupported:Null<String> = null;
		function visit(pattern:TySwitchCaseCoverage, contributes:Bool):Void {
			switch (pattern) {
				case Member(field):
					if (!field.getOwner().equals(domain.getOwner()) || !field.getConstant().isEnumValue())
						unsupported = "pattern does not belong to the scrutinee enum abstract";
					else
						switch (field.getConstant().getKind()) {
							case IntValue(_) | StringValue(_) | BoolValue(_) | NullValue:
								hasMemberPattern = true;
								if (contributes) covered.set(field.getConstant().getCanonicalIdentity(), true);
							case Unresolved(reason): unsupported = reason;
							case Ordinary: unsupported = "pattern is not a constant enum member";
						}
				case CatchAll:
					if (contributes)
						catchAll = true;
				case NullOnly:
					// A null pattern covers no non-null member and is never a wildcard.
					if (contributes)
						covered.set(new TyFieldConstant(NullValue).getCanonicalIdentity(), true);
				case Guarded(inner):
					visit(inner, false);
				case Alternatives(items):
					for (item in items)
						visit(item, contributes);
				case Unsupported(reason):
					unsupported = reason;
			}
		}
		for (pattern in cases)
			visit(pattern, true);
		if (unsupported != null)
			return Indeterminate(unsupported);
		if (catchAll)
			return Exhaustive;
		// Haxe accepts null input even without a named null member. Diagnostic
		// exhaustiveness cannot prove that such an input initializes a result.
		if (requireNullCoverage && !covered.exists(new TyFieldConstant(NullValue).getCanonicalIdentity()))
			return NonExhaustiveWildcard;
		final seen = new StringMap<Bool>();
		final missing = new Array<TyFieldInfo>();
		for (member in domain.getMembers()) {
			final constant = member.field.getConstant();
			switch (constant.getKind()) {
				case NullValue:
					// Haxe excludes null from the values required for exhaustiveness,
					// even when the enum abstract names that null value explicitly.
					if (!requireNullCoverage)
						continue;
				case Unresolved(reason):
					return Indeterminate(reason);
				case Ordinary:
					return Indeterminate("enum domain contains an ordinary field");
				case IntValue(_) | StringValue(_) | BoolValue(_):
			}
			final key = constant.getCanonicalIdentity();
			if (!seen.exists(key) && !covered.exists(key))
				missing.push(member.field);
			seen.set(key, true);
		}
		if (missing.length == 0)
			return Exhaustive;
		// Without a member pattern, failure of every guard leaves the whole
		// scrutinee unmatched. A member pattern introduces named alternatives,
		// even when its own guard prevents it from proving coverage.
		return hasMemberPattern ? NonExhaustive(missing) : NonExhaustiveWildcard;
	}
}
