/** A return retains its lexical term and diagnostic position until body constraints settle. */
typedef TyReturnEvidence = {
	final term:TyInferenceTerm;
	final position:HxPos;
}

/**
	Collects checked return evidence for one source function during inference.
	Nested functions use separate states. Copies isolate speculative inference
	from the traversal that records the final declaration and control catalogs.
	Terms carry identities, not a solver: copied states resolve them through the
	copy's inference owner so speculative constraints cannot affect the original.
 */
class TyFunctionReturnState {
	public final target:TyControlTarget;
	public final expected:Null<TyType>;

	final values:Array<TyReturnEvidence>;

	public function new(target:TyControlTarget, expected:Null<TyType>) {
		this.target = target;
		this.expected = expected;
		this.values = [];
	}

	public function record(term:TyInferenceTerm, position:HxPos):Void
		values.push({term: term, position: position});

	public function getValues():Array<TyReturnEvidence>
		return values.copy();

	public function copy():TyFunctionReturnState {
		final result = new TyFunctionReturnState(target, expected);
		for (value in values)
			result.record(value.term, value.position);
		return result;
	}
}
