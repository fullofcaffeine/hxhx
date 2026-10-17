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
	PInt(value:Int);
	PEnumValue(name:String);
	PEnumExtract(name:String, args:Array<HxSwitchPattern>);
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
	POr(patterns:Array<HxSwitchPattern>);
}
