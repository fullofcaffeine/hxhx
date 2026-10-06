import TyControlTarget.TyControlTargetKind;

/**
	Records and replays the exact function and loop destinations selected by typing.

	The root function remains active throughout its body. Lexical brace scopes do
	not enter this stack. A nested function hides enclosing loops from break and
	continue, while returns select the nearest active function.
	Speculative inference receives copied mutable state and cannot consume replay.
	A field initializer has its own root identity but cannot receive a return.
 */
class TyControlScope {
	final ownerIdentity:String;
	final sourceRevision:String;
	final targets:Array<TyControlTarget>;
	final active:Array<TyControlTarget>;
	var replay:Bool;
	var cursor:Int;
	final returnStates:Array<TyFunctionReturnState>;

	public function new(ownerIdentity:String, sourceRevision:String, rootKind:TyControlTargetKind = Function) {
		if (rootKind == Loop)
			throw "control scope root must be a function or initializer";
		this.ownerIdentity = ownerIdentity;
		this.sourceRevision = sourceRevision;
		this.targets = [
			new TyControlTarget({
				ownerIdentity: ownerIdentity,
				sourceRevision: sourceRevision,
				ordinal: 0,
				kind: rootKind,
				sourceIdentity: "root"
			})
		];
		this.active = [targets[0]];
		this.replay = false;
		this.cursor = 1;
		this.returnStates = [];
	}

	/** Internal copies preserve immutable target objects and isolate each mutable traversal. */
	static function copyState(source:TyControlScope, replay:Bool, reset:Bool):TyControlScope {
		final result = new TyControlScope(source.ownerIdentity, source.sourceRevision, source.getRoot().getKind());
		result.targets.resize(0);
		for (target in source.targets)
			result.targets.push(target);
		result.active.resize(0);
		for (target in (reset ? [source.targets[0]] : source.active))
			result.active.push(target);
		result.cursor = reset ? 1 : source.cursor;
		result.replay = replay;
		if (!reset)
			for (state in source.returnStates)
				result.returnStates.push(state.copy());
		return result;
	}

	public function copy():TyControlScope
		return copyState(this, replay, false);

	public function createReplay():TyControlScope
		return copyState(this, true, true);

	public function copyForInference():TyControlScope
		return copyState(this, false, false);

	public function getRoot():TyControlTarget
		return targets[0];

	/** Start return collection only after entering its exact source function. */
	public function beginReturns(target:TyControlTarget, expected:Null<TyType>):Void {
		if (returnTarget() != target)
			throw "return collection requires the active function target";
		returnStates.push(new TyFunctionReturnState(target, expected));
	}

	public function currentReturns():Null<TyFunctionReturnState> {
		if (returnStates.length == 0)
			return null;
		final state = returnStates[returnStates.length - 1];
		return state.target == returnTarget() ? state : null;
	}

	public function finishReturns(target:TyControlTarget):Array<TyFunctionReturnState.TyReturnEvidence> {
		final state = currentReturns();
		if (state == null || state.target != target)
			throw "return collection ended outside its function";
		returnStates.pop();
		return state.getValues();
	}

	/** Enter a source function or loop in the same preorder used by typed-body replay. */
	public function enter(kind:TyControlTargetKind, sourceIdentity:String):TyControlTarget {
		if (kind == Initializer)
			throw "initializer control identity must be a traversal root";
		final target = if (replay) {
			if (cursor >= targets.length)
				throw "control target replay produced more targets than typing";
			final recorded = targets[cursor++];
			if (recorded.getKind() != kind
				|| recorded.getSourceIdentity() != sourceIdentity
				|| recorded.getParent() != active[active.length - 1])
				throw "control target replay differs from source traversal";
			recorded;
		} else {
			final allocated = new TyControlTarget({
				ownerIdentity: ownerIdentity,
				sourceRevision: sourceRevision,
				ordinal: targets.length,
				kind: kind,
				sourceIdentity: sourceIdentity,
				parent: active[active.length - 1]
			});
			targets.push(allocated);
			allocated;
		};
		active.push(target);
		return target;
	}

	public function exit(target:TyControlTarget):Void {
		if (active.length <= 1 || active[active.length - 1] != target)
			throw "control scope exit does not match its active target";
		active.pop();
	}

	public function returnTarget():TyControlTarget {
		var index = active.length;
		while (index > 0) {
			final target = active[--index];
			if (target.getKind() == Function)
				return target;
		}
		throw "return has no enclosing function";
	}

	public function loopTarget():Null<TyControlTarget> {
		var index = active.length;
		while (index > 0) {
			final target = active[--index];
			switch target.getKind() {
				case Loop:
					return target;
				case Function | Initializer:
					return null;
			}
		}
		return null;
	}

	public function assertReplayComplete():Void {
		if (!replay || cursor != targets.length || active.length != 1 || returnStates.length != 0)
			throw "control target replay did not consume the exact source traversal";
	}
}
