import haxe.ds.StringMap;

/** Resolved coverage evidence; a guard never proves that a value is covered. */
enum TySwitchCaseCoverage {
	Member(field:TyFieldInfo);
	CatchAll;
	Guarded(pattern:TySwitchCaseCoverage);
	Alternatives(cases:Array<TySwitchCaseCoverage>);
	Unsupported(reason:String);
}

/** Explicit results prevent an unsupported pattern from masquerading as complete coverage. */
enum TySwitchCoverageResult {
	Exhaustive;
	NonExhaustive(missing:Array<TyFieldInfo>);
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

	public function analyze(cases:Array<TySwitchCaseCoverage>):TySwitchCoverageResult {
		final covered = new StringMap<Bool>();
		var catchAll = false;
		var unsupported:Null<String> = null;
		function visit(pattern:TySwitchCaseCoverage, contributes:Bool):Void {
			switch (pattern) {
				case Member(field):
					if (!field.getOwner().equals(domain.getOwner()) || !field.getConstant().isEnumValue())
						unsupported = "pattern does not belong to the scrutinee enum abstract";
					else
						switch (field.getConstant().getKind()) {
							case IntValue(_) | StringValue(_) | BoolValue(_):
								if (contributes) covered.set(field.getConstant().getCanonicalIdentity(), true);
							case Unresolved(reason): unsupported = reason;
							case Ordinary: unsupported = "pattern is not a constant enum member";
						}
				case CatchAll:
					if (contributes)
						catchAll = true;
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
		final seen = new StringMap<Bool>();
		final missing = new Array<TyFieldInfo>();
		for (member in domain.getMembers()) {
			final constant = member.field.getConstant();
			switch (constant.getKind()) {
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
		return missing.length == 0 ? Exhaustive : NonExhaustive(missing);
	}
}
