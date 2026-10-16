/**
	Retain selected declarations beside the authored switch patterns.

	The original syntax remains available to macros. Named patterns are traversed
	in source order, including nested payloads, to pair each projected occurrence
	with its selection. A changed input type or source pattern invalidates the pair.
 */
class TypedSwitchPatterns {
	final input:TyType;
	final inputKey:String;
	final sourceIdentity:String;
	final selections:Array<Null<TypedNamedPattern>>;

	public function new(input:TyType, patterns:Array<HxSwitchPattern>, selections:Array<Null<TypedNamedPattern>>) {
		this.input = input;
		inputKey = input.getSemanticKey();
		sourceIdentity = identity(patterns);
		if (named(patterns).length != selections.length)
			throw "named pattern selections do not match their source occurrences";
		this.selections = selections.copy();
	}

	static function identity(patterns:Array<HxSwitchPattern>):String
		return TypedBodyFingerprint.exactExpression(ESwitch(ENull, patterns, []));

	public function assertInput(input:TyType, patterns:Array<HxSwitchPattern>):Void {
		if (input.getSemanticKey() != inputKey || identity(patterns) != sourceIdentity)
			throw "named pattern selections have stale switch input or syntax";
	}

	public function getSelections():Array<Null<TypedNamedPattern>>
		return selections.copy();

	/** Inline specialization changes type arguments, while the selected declarations and authored cases stay the same. */
	@:allow(TypedExpr)
	function substituteTypes(bindings:haxe.ds.StringMap<TyType>, patterns:Array<HxSwitchPattern>):TypedSwitchPatterns {
		assertInput(input, patterns);
		return new TypedSwitchPatterns(TyTypeSubstitution.apply(input, bindings), patterns, selections);
	}

	public function getSemanticKey():String
		return CompilerCacheIdentity.encode([inputKey, sourceIdentity].concat([
			for (selection in selections)
				selection == null ? "unresolved" : selection.getSemanticKey()
		]));

	/** One traversal order serves typing, projection, and exact occurrence checks. */
	public static function named(patterns:Array<HxSwitchPattern>):Array<HxSwitchPattern> {
		final result = new Array<HxSwitchPattern>();
		function visit(pattern:HxSwitchPattern):Void {
			switch pattern {
				case PEnumValue(_):
					result.push(pattern);
				case PEnumExtract(_, children):
					result.push(pattern);
					for (child in children)
						visit(child);
				case PObject(_, children) | PArray(children) | POr(children):
					for (child in children)
						visit(child);
				case PCapture(_, child) | PExtractor(_, child) | PLengthGuard(child, _, _) | PStartsWithGuard(child, _, _) | PIntEqualsGuard(child, _, _) |
					PIntCompareGuard(child, _, _, _) | PParsedIntSwitchGuard(child, _, _, _) | PUnsupportedGuard(child):
					visit(child);
				case PNull | PWildcard | PBool(_) | PString(_) | PInt(_) | PBind(_):
			}
		}
		for (pattern in patterns)
			visit(pattern);
		return result;
	}
}
