/** Ordinary guards remain source expressions until shared typing and control lowering. */
function condition(pattern:HxSwitchPattern):Null<HxExpr>
	return switch pattern {
		case PGuard(_, value): value;
		case _: null;
	};

function pattern(pattern:HxSwitchPattern):HxSwitchPattern
	return switch pattern {
		case PGuard(inner, _): inner;
		case _: pattern;
	};

function has(patterns:Array<HxSwitchPattern>):Bool {
	if (patterns != null)
		for (pattern in patterns)
			if (condition(pattern) != null)
				return true;
	return false;
}

/** Guard operands are ordinary typed children, after the input and case bodies. */
function children(patterns:Array<HxSwitchPattern>, values:Array<TypedExpr>, offset:Int):Array<TypedExpr> {
	final count = has(patterns) ? patterns.length : 0;
	if (values.length != offset + count)
		throw "typed switch lost its aligned guard operands";
	return values.slice(offset);
}

/** Replace source conditions only with the corresponding typed child reconstruction. */
function project(patterns:Array<HxSwitchPattern>, guards:Array<TypedExpr>, emit:TypedExpr->HxExpr):Array<HxSwitchPattern> {
	if (guards.length != (has(patterns) ? patterns.length : 0))
		throw "switch projection lost its aligned guard operands";
	return [
		for (index in 0...patterns.length)
			switch patterns[index] {
				case PGuard(inner, _):
					PGuard(inner, emit(guards[index]));
				case other:
					other;
			}
	];
}
