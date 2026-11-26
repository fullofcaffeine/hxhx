/**
	Preserve authored switch patterns separately from selected declaration facts.
	Typing resolves names and case-local bindings. Ordinary guards retain their
	complete source expression; shared control lowering evaluates them only after
	a pattern matches. General extractor execution still has a separate lowering
	contract. Unsupported source patterns remain explicit and cannot count as
	exhaustive coverage.
 */
enum HxSwitchPattern {
	PNull;
	PWildcard;
	PBool(value:Bool);
	PString(value:String);

	/**
		`charCodeOf` keeps the string of a `case "x".code:` pattern: upstream Haxe 4.3.7 keeps the
		field access `"x".code` in the syntax tree. Only authored parsing
		(`ParserStage.parseAuthored`, the parse oracle) sets it; the value is the code either way
		(haxe_ocaml-ac5i9.3).
	**/
	PInt(value:Int, ?charCodeOf:String);

	/**
		A Float constant such as `1.5`, `-2.5`, `1e3` or `.5`, matched by
		numeric equality as upstream Haxe does. `text` is a portable decimal
		spelling (see `HxFloatPatternText`): it always has a leading digit and a
		`.` or exponent, so every target can print it as a Float literal.
		Use `HxFloatPatternText.value` for the number itself. An Int constant
		in a Float switch stays `PInt`.
	**/
	PFloat(text:String);

	/**
		`castWritten` marks a `case cast Array:` class-value pattern: upstream Haxe 4.3.7 keeps the
		`ECast` in the syntax tree. Only authored parsing (`ParserStage.parseAuthored`, the parse
		oracle) sets it; ordinary parsing reads the pattern as the class value (haxe_ocaml-ac5i9.6).
	**/
	PEnumValue(name:String, ?castWritten:Bool);

	/** Only the parser's bare final `_` can cover an unwritten required payload suffix. */
	PEnumExtract(name:String, args:Array<HxSwitchPattern>, ?bareWildcardSuffix:Bool);

	PObject(fieldNames:Array<String>, fieldPatterns:Array<HxSwitchPattern>);
	PCapture(name:String, pattern:HxSwitchPattern);
	PArray(items:Array<HxSwitchPattern>);
	PExtractor(extractorText:String, resultPattern:HxSwitchPattern);

	/** The authored condition executes in the matched case's binding scope. */
	PGuard(pattern:HxSwitchPattern, condition:HxExpr);

	/** A consumed pattern whose semantics are not represented, such as a macro quotation. */
	PUnsupportedPattern(pattern:HxSwitchPattern);

	PBind(name:String);

	/**
		OR-pattern list: `case a | b | c:`

		Bring-up constraint
		- This is parsed and lowered as a boolean OR of each sub-pattern’s
		  condition against the scrutinee. Backends may preserve bindings when all
		  alternatives bind the same names from the same value paths.
		- This is *not* the full upstream pattern algebra; it exists primarily to
		  support harness-style code like:
		  `case 'Linux' | 'Windows': ...`
	**/
	/**
		`caseList` is true for a comma-separated case list (`case A, B:`), which upstream keeps as
		several case values, and null for `A | B`. Both match the same values.
	**/
	POr(patterns:Array<HxSwitchPattern>, ?caseList:Bool);
}
