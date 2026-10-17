/** A source operand stays in its authored position, including an unexpanded spread. */
enum TyCallOperandKind {
	Value;
	Spread;
}

/** Candidate parameter assignments; no target placeholders, arrays, or conversions are emitted. */
enum TyCallArgumentSlot {
	Omitted;
	Supplied(sourceIndex:Int);
	RestElements(sourceIndices:Array<Int>);
	RestSpread(sourceIndex:Int);
}

/** Failures retain source and parameter indices for callable-specific diagnostics. */
enum TyCallAlignmentFailure {
	MissingRequired(parameterIndex:Int);
	TooManyArguments(sourceIndex:Int);
	IncompatibleArgument(sourceIndex:Int, parameterIndex:Int);
	UnprovedArgument(sourceIndex:Int, parameterIndex:Int);
	UnexpectedSpread(sourceIndex:Int, parameterIndex:Int);
	MixedRestSpread(sourceIndex:Int);
	UnsupportedRestPosition(parameterIndex:Int);
}

/** An alignment trial is not the sealed typed call: conversions and type-use evidence come later. */
enum TyCallAlignmentResult {
	Aligned(slots:Array<TyCallArgumentSlot>);
	Rejected(failure:TyCallAlignmentFailure);
}

/**
	Align operands using read-only directional compatibility supplied by shared typing.

	A failed optional skip restores the original mismatch when its suffix has a
	type error. A missing required suffix retains its own diagnostic. These are
	separate Haxe 4.3.7 outcomes. No speculative slot array escapes on failure.
	The compatibility callback must not mutate inference state or publish effects;
	this helper neither infers types nor decides whether a conversion is valid.
	Unknown compatibility never becomes a successful assignment.
 */
function align(parameters:Array<TyFunctionParameter>, operands:Array<TyCallOperandKind>,
		compatibility:(sourceIndex:Int, parameterIndex:Int, spread:Bool) -> TyCallArgumentCompatibility):TyCallAlignmentResult {
	final params = [for (parameter in parameters) TyFunctionParameter.copy(parameter)];
	final sources = operands.copy();
	for (index in 0...params.length - 1)
		if (params[index].isRest)
			return Rejected(UnsupportedRestPosition(index));

	function prepend(slot:TyCallArgumentSlot, result:TyCallAlignmentResult):TyCallAlignmentResult {
		return switch (result) {
			case Aligned(slots): Aligned([slot].concat(slots));
			case Rejected(_): result;
		};
	}
	function check(source:Int, parameter:Int, spread:Bool):Null<TyCallAlignmentFailure> {
		return switch (compatibility(source, parameter, spread)) {
			case Compatible: null;
			case Incompatible: IncompatibleArgument(source, parameter);
			case Unknown: UnprovedArgument(source, parameter);
		};
	}
	function visit(parameter:Int, source:Int):TyCallAlignmentResult {
		if (parameter == params.length)
			return source == sources.length ? Aligned([]) : Rejected(TooManyArguments(source));
		final param = params[parameter];
		if (param.isRest) {
			for (index in source...sources.length)
				if (sources[index] == Spread) {
					if (sources.length - source != 1)
						return Rejected(MixedRestSpread(index));
					final failure = check(index, parameter, true);
					return failure == null ? Aligned([RestSpread(index)]) : Rejected(failure);
				}
			final elements = new Array<Int>();
			for (index in source...sources.length) {
				final failure = check(index, parameter, false);
				if (failure != null)
					return Rejected(failure);
				elements.push(index);
			}
			return Aligned([RestElements(elements)]);
		}
		if (source == sources.length)
			return param.isOptional ? prepend(Omitted, visit(parameter + 1, source)) : Rejected(MissingRequired(parameter));
		final failure = sources[source] == Spread ? UnexpectedSpread(source, parameter) : check(source, parameter, false);
		if (failure == null)
			return prepend(Supplied(source), visit(parameter + 1, source + 1));
		if (failure.match(UnprovedArgument(_, _)))
			return Rejected(failure);
		if (param.isOptional && sources.length - source < params.length - parameter) {
			final skipped = visit(parameter + 1, source);
			switch (skipped) {
				case Aligned(_):
					return prepend(Omitted, skipped);
				case Rejected(MissingRequired(_)):
					return skipped;
				case Rejected(UnprovedArgument(_, _)):
					return skipped;
				case Rejected(_):
			}
		}
		return Rejected(failure);
	}
	return visit(0, 0);
}
