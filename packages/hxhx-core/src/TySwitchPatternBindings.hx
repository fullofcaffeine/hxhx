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
	in exactly the order recorded by the typer. Array elements and structural
	fields retain their declared types, including through nested captures; branch
	arithmetic must not become Dynamic merely because a pattern introduced a local.
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

	static function analyzeOr(patterns:Array<HxSwitchPattern>, baseType:TyType,
			enumArguments:Null<(TyType, String, Int) -> Null<Array<TyType>>>):TySwitchPatternBindingAnalysis {
		if (patterns == null || patterns.length == 0)
			return emptyAnalysis();
		final alternatives = [for (pattern in patterns) analyze(pattern, baseType, enumArguments)];
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

	/** Keep nested array captures typed before branch operations are selected. */
	static function arrayItemType(type:TyType):TyType {
		var container = effectiveType(type);
		while (container.isNullable())
			container = container.unwrapNull();
		final arguments = container.getTypeArguments();
		final identity = container.getNominalIdentity();
		final path = identity == null ? container.getUnresolvedPath() : identity.getCanonicalName();
		return arguments.length == 1 && (path == "Array" || path == "haxe.Array") ? arguments[0] : TyType.fromHintText("Dynamic");
	}

	static function analyze(pattern:HxSwitchPattern, baseType:TyType,
			enumArguments:Null<(TyType, String, Int) -> Null<Array<TyType>>>):TySwitchPatternBindingAnalysis {
		if (pattern == null)
			return emptyAnalysis();
		return switch (pattern) {
			case PBind(name):
				bindingFact(name, baseType);
			case PCapture(name, inner):
				mergeIndependent([bindingFact(name, baseType), analyze(inner, baseType, enumArguments)]);
			case PEnumExtract(name, arguments):
				final children = arguments == null ? [] : arguments;
				final types = enumArguments == null ? null : enumArguments(baseType, name, children.length);
				if (types != null && types.length != children.length)
					throw "enum pattern argument types do not match its payload patterns";
				mergeIndependent([
					for (i in 0...children.length)
						analyze(children[i], types == null ? TyType.fromHintText("Dynamic") : types[i], enumArguments)
				]);
			case PObject(fieldNames, fieldPatterns):
				if (fieldNames == null || fieldPatterns == null || fieldNames.length != fieldPatterns.length)
					throw "switch object pattern requires aligned fields";
				mergeIndependent([
					for (i in 0...fieldPatterns.length)
						analyze(fieldPatterns[i], effectiveType(TyStructuralFieldRead.resolve(effectiveType(baseType), fieldNames[i])), enumArguments)
				]);
			case PArray(items):
				final children = items == null ? [] : items;
				final itemType = arrayItemType(baseType);
				mergeIndependent([for (item in children) analyze(item, itemType, enumArguments)]);
			case PExtractor(_, resultPattern):
				analyze(resultPattern, TyType.fromHintText("Dynamic"), enumArguments);
			case PLengthGuard(inner, _, _), PStartsWithGuard(inner, _, _), PIntEqualsGuard(inner, _, _), PIntCompareGuard(inner, _, _, _),
				PParsedIntSwitchGuard(inner, _, _, _), PUnsupportedGuard(inner):
				analyze(inner, baseType, enumArguments);
			case POr(patterns):
				analyzeOr(patterns, baseType, enumArguments);
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
	public static function declare(environment:Null<TyFunctionEnv>, pattern:HxSwitchPattern, baseType:TyType,
			?enumArguments:(TyType, String, Int) -> Null<Array<TyType>>):Array<TyLocalBinding> {
		if (environment == null)
			return [];
		final analysis = analyze(pattern, baseType, enumArguments);
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
