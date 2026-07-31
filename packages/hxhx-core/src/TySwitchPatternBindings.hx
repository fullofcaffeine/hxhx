import haxe.ds.StringMap;

private typedef TySwitchPatternBindingFact = {
	var name:String;
	var type:TyType;
};

private typedef TySwitchPatternBindingAnalysis = {
	final declarations:Array<TySwitchPatternBindingFact>;
	final occurrences:Array<TySwitchPatternBindingFact>;
};

/**
	Selects the function-local declarations introduced by one switch pattern.

	An OR-pattern can contain several source occurrences of the same name, but
	every alternative hands the case body one logical local. This owner validates
	that contract before it mutates the function scope, declares each logical
	local once, and returns one binding reference for every source occurrence.
	Typed-body replay calls the same operation, so it consumes the declarations
	in exactly the order recorded by the typer.
**/
class TySwitchPatternBindings {
	static function effectiveType(type:TyType):TyType
		return type == null || type.isUnknown() ? TyType.fromHintText("Dynamic") : type;

	static function emptyAnalysis():TySwitchPatternBindingAnalysis
		return {declarations: [], occurrences: []};

	static function bindingFact(name:String, type:TyType):TySwitchPatternBindingAnalysis {
		if (name == null || name.length == 0 || name == "_")
			return emptyAnalysis();
		final fact = {name: name, type: effectiveType(type)};
		return {declarations: [fact], occurrences: [fact]};
	}

	static function mergeIndependent(parts:Array<TySwitchPatternBindingAnalysis>):TySwitchPatternBindingAnalysis {
		final declarations = new Array<TySwitchPatternBindingFact>();
		final occurrences = new Array<TySwitchPatternBindingFact>();
		final declared = new StringMap<Bool>();
		for (part in parts) {
			for (fact in part.declarations) {
				if (declared.exists(fact.name))
					throw "Variable " + fact.name + " is bound multiple times";
				declared.set(fact.name, true);
				declarations.push(fact);
			}
			for (fact in part.occurrences)
				occurrences.push(fact);
		}
		return {declarations: declarations, occurrences: occurrences};
	}

	static function analyzeOr(patterns:Array<HxSwitchPattern>, baseType:TyType):TySwitchPatternBindingAnalysis {
		if (patterns == null || patterns.length == 0)
			return emptyAnalysis();
		final alternatives = [for (pattern in patterns) analyze(pattern, baseType)];
		final declarations = [
			for (fact in alternatives[0].declarations)
				{name: fact.name, type: fact.type}
		];
		final expected = new StringMap<Int>();
		for (index in 0...declarations.length)
			expected.set(declarations[index].name, index);
		for (alternativeIndex in 1...alternatives.length) {
			final alternative = alternatives[alternativeIndex];
			final actual = new StringMap<TySwitchPatternBindingFact>();
			for (fact in alternative.declarations) {
				if (!expected.exists(fact.name))
					throw "Variable " + fact.name + " must appear exactly once in each sub-pattern";
				actual.set(fact.name, fact);
			}
			for (expectedFact in declarations) {
				final actualFact = actual.get(expectedFact.name);
				if (actualFact == null)
					throw "Variable " + expectedFact.name + " must appear exactly once in each sub-pattern";
				final unified = TyType.unify(expectedFact.type, actualFact.type);
				if (unified == null)
					throw actualFact.type.getDisplay() + " should be " + expectedFact.type.getDisplay();
				expectedFact.type = unified;
			}
		}
		final occurrences = new Array<TySwitchPatternBindingFact>();
		for (alternative in alternatives)
			for (fact in alternative.occurrences)
				occurrences.push(fact);
		return {declarations: declarations, occurrences: occurrences};
	}

	static function analyze(pattern:HxSwitchPattern, baseType:TyType):TySwitchPatternBindingAnalysis {
		if (pattern == null)
			return emptyAnalysis();
		return switch (pattern) {
			case PBind(name):
				bindingFact(name, baseType);
			case PCapture(name, inner):
				mergeIndependent([bindingFact(name, baseType), analyze(inner, baseType)]);
			case PEnumExtract(_, arguments):
				final children = arguments == null ? [] : arguments;
				mergeIndependent([for (argument in children) analyze(argument, TyType.fromHintText("Dynamic"))]);
			case PObject(_, fieldPatterns):
				final children = fieldPatterns == null ? [] : fieldPatterns;
				mergeIndependent([
					for (fieldPattern in children)
						analyze(fieldPattern, TyType.fromHintText("Dynamic"))
				]);
			case PArray(items):
				final children = items == null ? [] : items;
				mergeIndependent([for (item in children) analyze(item, TyType.fromHintText("Dynamic"))]);
			case PExtractor(_, resultPattern):
				analyze(resultPattern, TyType.fromHintText("Dynamic"));
			case PLengthGuard(inner, _, _), PStartsWithGuard(inner, _, _), PIntEqualsGuard(inner, _, _), PIntCompareGuard(inner, _, _, _),
				PParsedIntSwitchGuard(inner, _, _, _), PUnsupportedGuard(inner):
				analyze(inner, baseType);
			case POr(patterns):
				analyzeOr(patterns, baseType);
			case _:
				emptyAnalysis();
		}
	}

	/**
		Declare one logical local per binding name and return every occurrence.

		The analysis runs first, so an invalid pattern cannot leave a partially
		mutated lexical scope. In replay mode, `environment.declareLocal` consumes
		the already-recorded symbol instead of allocating a replacement identity.
	**/
	public static function declare(environment:Null<TyFunctionEnv>, pattern:HxSwitchPattern, baseType:TyType):Array<TyLocalBinding> {
		if (environment == null)
			return [];
		final analysis = analyze(pattern, baseType);
		final symbols = new StringMap<TySymbol>();
		for (fact in analysis.declarations)
			symbols.set(fact.name, environment.declareLocal(fact.name, fact.type, PatternVariable));
		return [
			for (fact in analysis.occurrences) {
				final symbol = symbols.get(fact.name);
				if (symbol == null) throw "switch pattern binding analysis lost local " + fact.name;
				symbol.toBinding();
			}
		];
	}
}
