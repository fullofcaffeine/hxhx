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
	/**
		Return syntax-owned names without inferring the switch input or payload types.
		Guards, extractors, and unsupported syntax need a separate source traversal;
		null prevents a caller from treating partial names as complete visibility.
	**/
	public static function sourceNames(pattern:HxSwitchPattern):Null<Array<String>> {
		function supported(value:HxSwitchPattern):Bool {
			return switch value {
				case PGuard(_, _) | PExtractor(_, _) | PUnsupportedPattern(_): false;
				case PCapture(_, inner): supported(inner);
				case PEnumExtract(_, children) | PArray(children) | POr(children): children.filter(child -> !supported(child)).length == 0;
				case PObject(_, children): children.filter(child -> !supported(child)).length == 0;
				case _: true;
			};
		}
		return supported(pattern) ? analyze(pattern, TyType.unknown(), null).declarations.map(fact -> fact.name) : null;
	}

	/** Count source occurrences without allocating replacement local identities during lowering. */
	public static function occurrenceCount(pattern:HxSwitchPattern):Int
		return analyze(pattern, TyType.unknown(), null).occurrences.length;

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

	static function analyzeOr(patterns:Array<HxSwitchPattern>, baseType:TyType, enumArguments:Null<(TyType, String, Int, Bool) -> Null<Array<TyType>>>,
			?elements:Array<TyType>, ?extractorType:(String, TyType) -> Null<TyType>):TySwitchPatternBindingAnalysis {
		if (patterns == null || patterns.length == 0)
			return emptyAnalysis();
		final alternatives = [
			for (pattern in patterns)
				analyze(pattern, baseType, enumArguments, elements, extractorType)
		];
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

	/**
		`elements` holds the type of each element when the switch subject is an array literal:
		Haxe 4.3.7 matches `switch [shape, paint]` position by position, so `case [Circle(r), Solid(c)]`
		binds each element with its own type, not with the array's joined element type.
	**/
	static function analyze(pattern:HxSwitchPattern, baseType:TyType, enumArguments:Null<(TyType, String, Int, Bool) -> Null<Array<TyType>>>,
			?elements:Array<TyType>, ?extractorType:(String, TyType) -> Null<TyType>):TySwitchPatternBindingAnalysis {
		if (pattern == null)
			return emptyAnalysis();
		return switch (pattern) {
			case PBind(name):
				bindingFact(name, baseType);
			case PCapture(name, inner):
				mergeIndependent([
					bindingFact(name, baseType),
					analyze(inner, baseType, enumArguments, elements, extractorType)
				]);
			case PEnumExtract(name, arguments, provenance):
				final children = arguments == null ? [] : arguments;
				final types = enumArguments == null ? null : enumArguments(baseType, name, children.length,
					TyEnumPatternArguments.hasWildcardSuffix(children, provenance));
				if (types != null && types.length != children.length)
					throw "enum pattern argument types do not match its payload patterns";
				mergeIndependent([
					for (i in 0...children.length)
						analyze(children[i], types == null ? TyType.fromHintText("Dynamic") : types[i], enumArguments, null, extractorType)
				]);
			case PObject(fieldNames, fieldPatterns):
				if (fieldNames == null || fieldPatterns == null || fieldNames.length != fieldPatterns.length)
					throw "switch object pattern requires aligned fields";
				mergeIndependent([
					for (i in 0...fieldPatterns.length)
						analyze(fieldPatterns[i], effectiveType(TyStructuralFieldRead.resolve(effectiveType(baseType), fieldNames[i])), enumArguments, null,
							extractorType)
				]);
			case PArray(items):
				final children = items == null ? [] : items;
				if (elements != null && elements.length == children.length) mergeIndependent([
					for (i in 0...children.length)
						analyze(children[i], elements[i], enumArguments, null, extractorType)
				]); else {
					final itemType = arrayItemType(baseType);
					mergeIndependent([
						for (item in children)
							analyze(item, itemType, enumArguments, null, extractorType)
					]);
				}
			case PExtractor(extractorText, resultPattern):
				// `_.get() => items` binds `items` with the extractor's result, where `_` is the
				// matched value. Without a typing callback the result stays Dynamic.
				final extracted = extractorType == null ? null : extractorType(extractorText, baseType);
				analyze(resultPattern, extracted == null ? TyType.fromHintText("Dynamic") : extracted, enumArguments, null, extractorType);
			case PGuard(inner, _), PUnsupportedPattern(inner):
				analyze(inner, baseType, enumArguments, elements, extractorType);
			case POr(patterns):
				analyzeOr(patterns, baseType, enumArguments, elements, extractorType);
			case _:
				emptyAnalysis();
		}
	}

	/**
		Type an extractor (`_.get()`) with `_` bound to the matched type. The binding lives in a
		copied environment, so it never enters the typed-body replay catalog. The function's
		inference records the result, and the typed-body replay reads it back: parsing the text
		again would give new syntax with no recorded facts (`_.get()` on a structural `Ref` needs
		its callback alignment). Null when the text does not parse or its type stays unknown.
	**/
	public static function extractorResult(text:String, matched:TyType, environment:TyFunctionEnv,
			typeOf:(HxExpr, TyFunctionEnv) -> Null<TyType>):Null<TyType> {
		if (text == null || environment == null || matched == null || matched.isUnknown())
			return null;
		final key = text + "\n" + matched.getSemanticKey();
		final inference = environment.getInference();
		final known = inference.knownExtractorResult(key);
		if (known != null)
			return known;
		// After sealing, freshly parsed syntax has no recorded facts to replay; the typing pass
		// has already recorded every extractor it could type.
		if (inference.isSealed())
			return null;
		final expression = try HxParser.parseExprText(text) catch (_:Dynamic) null;
		if (expression == null)
			return null;
		final trial = environment.copyForInference();
		trial.enterLexicalScope();
		trial.declareLocal("_", matched, PatternVariable);
		final result = try typeOf(expression, trial) catch (_:Dynamic) null;
		if (result == null || result.isUnknown())
			return null;
		inference.recordExtractorResult(key, result);
		return result;
	}

	/** The element types of an array-literal switch subject, or null for any other subject. */
	public static function literalElements(subject:HxExpr, typeOf:HxExpr->TyType):Null<Array<TyType>> {
		return switch subject {
			case EParenthesized(inner, _): literalElements(inner, typeOf);
			case EArrayDecl(values) if (values != null && values.length > 0): [for (value in values) typeOf(value)];
			case _: null;
		};
	}

	/**
		Declare one logical local per binding name and return every occurrence.

		The analysis runs first, so an invalid pattern cannot leave a partially
		mutated lexical scope. In replay mode, `environment.declareLocal` consumes
		the already-recorded symbol instead of allocating a replacement identity.
	**/
	public static function declare(environment:Null<TyFunctionEnv>, pattern:HxSwitchPattern, baseType:TyType,
			?enumArguments:(TyType, String, Int, Bool) -> Null<Array<TyType>>, ?elements:Array<TyType>,
			?extractorType:(String, TyType) -> Null<TyType>):Array<TyLocalBinding> {
		if (environment == null)
			return [];
		final analysis = analyze(pattern, baseType, enumArguments, elements, extractorType);
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
