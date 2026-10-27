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
	final writtenShapes:Array<String>;

	public function new(input:TyType, patterns:Array<HxSwitchPattern>, selections:Array<Null<TypedNamedPattern>>) {
		this.input = input;
		inputKey = input.getSemanticKey();
		sourceIdentity = identity(patterns);
		if (named(patterns).length != selections.length)
			throw "named pattern selections do not match their source occurrences";
		this.selections = selections.copy();
		writtenShapes = named(patterns).map(writtenShape);
	}

	static function identity(patterns:Array<HxSwitchPattern>):String
		return TypedBodyFingerprint.exactExpression(ESwitch(ENull, patterns, []));

	public function assertInput(input:TyType, patterns:Array<HxSwitchPattern>):Void {
		if (input.getSemanticKey() != inputKey || identity(patterns) != sourceIdentity)
			throw "named pattern selections have stale switch input or syntax";
	}

	public function getSelections():Array<Null<TypedNamedPattern>>
		return selections.copy();

	static function writtenShape(pattern:HxSwitchPattern):String {
		return CompilerCacheIdentity.encode(switch pattern {
			case PEnumValue(name): ["value", name];
			case PEnumExtract(name, children): ["extract", name, Std.string(children.length)];
			case _: throw "written enum shape requires a named pattern";
		});
	}

	/**
		Complete executable patterns with wildcards for validated optional suffixes.

		Source patterns keep their written children. Projection may rename bindings,
		but must retain each named occurrence's kind, spelling, count, and order. The
		selected constructor keeps its full stored payload count; added wildcards do
		not create source bindings or borrow another occurrence's declaration.
	 */
	public function projectPayloads(patterns:Array<HxSwitchPattern>):Array<HxSwitchPattern> {
		final before = named(patterns);
		if (before.length != writtenShapes.length)
			throw "projected named pattern count differs from typing";
		for (index in 0...before.length)
			if (writtenShape(before[index]) != writtenShapes[index])
				throw "projected named pattern shape differs from its written occurrence";
		var cursor = 0;
		function visit(pattern:HxSwitchPattern):HxSwitchPattern {
			return switch pattern {
				case PEnumValue(_):
					cursor++;
					pattern;
				case PEnumExtract(name, children):
					final selection = selections[cursor++];
					final projected = [for (child in children) visit(child)];
					if (selection != null)
						switch selection.getKind() {
							case Constructor(_, _, _, arity):
								if (projected.length > arity)
									throw "projected enum payload exceeds its selected declaration";
								while (projected.length < arity)
									projected.push(PWildcard);
							case Constant(_):
						}
					PEnumExtract(name, projected);
				case PObject(names, children): PObject(names.copy(), [for (child in children) visit(child)]);
				case PArray(children): PArray([for (child in children) visit(child)]);
				case POr(children): POr([for (child in children) visit(child)]);
				case PGuard(child, guard): PGuard(visit(child), guard);
				case PCapture(name, child): PCapture(name, visit(child));
				case PExtractor(text, child): PExtractor(text, visit(child));
				case PUnsupportedPattern(child): PUnsupportedPattern(visit(child));
				case _: pattern;
			};
		}
		final projected = [for (pattern in patterns) visit(pattern)];
		final after = named(projected);
		if (cursor != selections.length || after.length != selections.length)
			throw "optional payload projection changed named occurrence order";
		for (index in 0...after.length)
			switch [before[index], after[index]] {
				case [PEnumValue(a), PEnumValue(b)] | [PEnumExtract(a, _), PEnumExtract(b, _)] if (a == b):
				case _:
					throw "optional payload projection changed named occurrence order";
			}
		return projected;
	}

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
				case PGuard(child, _) | PCapture(_, child) | PExtractor(_, child) | PUnsupportedPattern(child):
					visit(child);
				case PNull | PWildcard | PBool(_) | PString(_) | PInt(_) | PBind(_):
			}
		}
		for (pattern in patterns)
			visit(pattern);
		return result;
	}
}
