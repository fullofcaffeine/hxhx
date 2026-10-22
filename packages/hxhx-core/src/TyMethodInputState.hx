/** A speculative input solution cannot affect another overload or an earlier snapshot. */
@:allow(TyMethodInputState)
class TyMethodInputTrial {
	final owner:TyMethodInputState;
	final revision:Int;
	final declaration:TyDeclarationInfo;
	final sourceIdentity:String;
	final inputs:Array<TyType>;
	final signature:TyFunSig;
	final changed:Bool;

	@:allow(TyMethodInputState)
	function new(owner:TyMethodInputState, revision:Int, declaration:TyDeclarationInfo, sourceIdentity:String, signature:TyFunSig, changed:Bool) {
		this.owner = owner;
		this.revision = revision;
		this.declaration = declaration;
		this.sourceIdentity = sourceIdentity;
		this.signature = signature;
		this.changed = changed;
		this.inputs = signature.getArgs().copy();
	}

	/** Candidate ranking sees a fresh signature; declaration headers are never rewritten. */
	public function getSignature():TyFunSig
		return new TyFunSig(signature.getName(), signature.getIsStatic(), signature.getArgNames().copy(), inputs.copy(), signature.getArgOptional().copy(),
			signature.getArgRest().copy(), signature.getReturnType(), signature.getPos());
}

private typedef MethodInputSolution = {
	final declaration:TyDeclarationInfo;
	final sourceIdentity:String;
	final inputs:Array<TyType>;
};

/**
	Own caller evidence for omitted declaration inputs within one typing request.
	A trial only fills genuinely omitted inputs. Written types remain authoritative.
	Dynamic and null arguments supply no evidence. A callback can retain omitted
	unknown inputs until another caller supplies their types.
	The caller must finish overload ranking and compatibility checks before commit.
	The revision lets the typing driver discard prepared bodies after new evidence;
	this owner never changes a previously returned signature or typed body.
 */
class TyMethodInputState {
	final solutions = new haxe.ds.StringMap<MethodInputSolution>();
	var revision:Int = 0;

	public function new() {}

	public function getRevision():Int
		return revision;

	static function sourceIdentity(declaration:TyDeclarationInfo):String {
		final source = declaration.getSourceDeclaration();
		return source == null ? "extern" : CompilerCacheIdentity.encode([
			TypedFunctionDefault.sourceIdentity(HxFunctionDecl.getArgs(source)),
			TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(source))
		]);
	}

	static function omitted(declaration:TyDeclarationInfo, index:Int):Bool {
		final source = declaration.getSourceDeclaration();
		if (source == null || !HxFunctionDecl.getHasBody(source))
			return false;
		final arguments = HxFunctionDecl.getArgs(source);
		if (index >= arguments.length)
			return false;
		final hint = HxFunctionArg.getTypeHint(arguments[index]);
		return hint == null || StringTools.trim(hint).length == 0;
	}

	static function replaceInputs(signature:TyFunSig, inputs:Array<TyType>):TyFunSig {
		return new TyFunSig(signature.getName(), signature.getIsStatic(), signature.getArgNames().copy(), inputs.copy(), signature.getArgOptional().copy(),
			signature.getArgRest().copy(), signature.getReturnType(), signature.getPos());
	}

	/** Body evidence stays authoritative; only its still-open omitted slots read caller evidence. */
	public function signature(declaration:TyDeclarationInfo, body:TyFunSig):TyFunSig {
		final existing = solutions.get(declaration.getIdentity().getCanonicalKey());
		if (existing == null)
			return body;
		if (existing.declaration != declaration || existing.sourceIdentity != sourceIdentity(declaration))
			throw "method input evidence belongs to a changed declaration";
		final inputs = body.getArgs().copy();
		if (inputs.length != existing.inputs.length)
			throw "method input evidence changed parameter count";
		for (index in 0...inputs.length)
			if (inputs[index].isUnknown() && omitted(declaration, index))
				inputs[index] = existing.inputs[index];
		return replaceInputs(body, inputs);
	}

	/** Retain a callback's known shape while leaving unused inputs unresolved until later callers supply evidence. */
	static function fillOpen(expected:TyType, actual:TyType):TyType {
		if (actual.isDynamic() || actual.isNullLiteral() || actual.isUnknown() || actual.hasTypeParameter() || actual.hasOpenMethodParameter())
			return expected;
		if (expected.isUnknown())
			return actual.isFunction() || !actual.hasUnknownComponent() ? actual : expected;
		if (expected.isFunction() && actual.isFunction()) {
			final left = expected.getFunctionArguments();
			final right = actual.getFunctionArguments();
			if (left.length == right.length)
				return expected.withFunctionTypes([for (index in 0...left.length) fillOpen(left[index], right[index])],
					fillOpen(expected.getFunctionReturn(), actual.getFunctionReturn()));
		}
		// Established leaves retain their type. Ordinary compatibility, not
		// inference, decides whether a later argument can convert to that type.
		return expected;
	}

	/** Arguments are already aligned to parameter slots; overload selection remains the caller's responsibility. */
	public function trial(declaration:TyDeclarationInfo, body:TyFunSig, arguments:Array<TyType>):TyMethodInputTrial {
		final effective = signature(declaration, body);
		final inputs = effective.getArgs().copy();
		var changed = false;
		for (index in 0...inputs.length) {
			if (index >= arguments.length || !omitted(declaration, index))
				continue;
			final selected = fillOpen(inputs[index], arguments[index]);
			if (selected.getSemanticKey() != inputs[index].getSemanticKey()) {
				inputs[index] = selected;
				changed = true;
			}
		}
		return new TyMethodInputTrial(this, revision, declaration, sourceIdentity(declaration), replaceInputs(effective, inputs), changed);
	}

	/** Only a selected, still-current trial can publish new evidence. Repeated observations are idempotent. */
	public function commit(trial:TyMethodInputTrial):Bool {
		if (trial.owner != this || trial.revision != revision)
			throw "method input trial is foreign or stale";
		if (trial.sourceIdentity != sourceIdentity(trial.declaration))
			throw "method input trial belongs to changed source";
		if (!trial.changed)
			return false;
		final current = signature(trial.declaration, trial.declaration.getSignature()).getArgs();
		if (CompilerCacheIdentity.encode(current.map(type -> type.getSemanticKey())) == CompilerCacheIdentity.encode(trial.inputs.map(type ->
			type.getSemanticKey())))
			return false;
		solutions.set(trial.declaration.getIdentity().getCanonicalKey(), {
			declaration: trial.declaration,
			sourceIdentity: trial.sourceIdentity,
			inputs: trial.inputs.copy()
		});
		revision++;
		return true;
	}
}
