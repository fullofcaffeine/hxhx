/** Checked body facts retain inputs; an inferred result also requires evidence on every value-returning path. */
typedef TyMethodBodyResult = {
	final type:TyType;
	final complete:Bool;
	final parameters:Array<TyType>;
}

private typedef CheckedMethodResult = {
	final declaration:TyDeclarationInfo;
	final fingerprint:String;
	final type:TyType;
	final parameters:Array<TyType>;
	final assumptions:Array<String>;
}

/** Recursive reads can use a candidate only while its owning body is being rechecked. */
private typedef MethodResultFrame = {
	final type:TyType;
	final parameters:Array<TyType>;
	final assumptions:haxe.ds.StringMap<Bool>;
	var recursive:Bool;
}

/**
	Request-owned checked body inputs and results, separate from immutable declaration headers.
	The shared typer supplies the declaring-module computation. Targets and structural
	checks can consume its result without rewriting source annotations or binder owners.
	Recursive candidates come only from body evidence and must survive another pass.
	Incomplete cycles remain unresolved rather than publishing a guessed type.
 */
class TyMethodBodyResults {
	final checked = new haxe.ds.StringMap<CheckedMethodResult>();
	final active = new haxe.ds.StringMap<MethodResultFrame>();
	var infer:Null<TyDeclarationInfo->TyMethodBodyResult>;

	public function new() {}

	/** The typing request supplies its current loader; inference itself stays in the shared typer. */
	public function configure(infer:TyDeclarationInfo->TyMethodBodyResult):Void {
		this.infer = infer;
	}

	public function result(declaration:TyDeclarationInfo):TyType {
		return checkedResult(declaration, false);
	}

	/**
		Propagate reads of unfinished candidates to every enclosing computation.
		A checked child can still depend on an outer candidate, so cache hits must
		carry those assumptions too. Completed candidates no longer constrain reuse.
	 */
	function recordAssumptions(assumptions:Array<String>):Void {
		for (key in assumptions)
			if (active.exists(key))
				for (frame in active)
					frame.assumptions.set(key, true);
	}

	/** Written input annotations remain authoritative; only omitted slots consume checked body facts. */
	function parameters(declaration:TyDeclarationInfo, inferred:Array<TyType>):Array<TyType> {
		final original = declaration.getSignature().getArgs();
		if (inferred.length != original.length)
			throw "method body input count differs from its declaration";
		final source = declaration.getSourceDeclaration();
		final arguments = source == null ? [] : HxFunctionDecl.getArgs(source);
		return [
			for (index in 0...original.length) {
				final hint = index < arguments.length ? HxFunctionArg.getTypeHint(arguments[index]) : "written";
				original[index].isUnknown()
			&& (hint == null || StringTools.trim(hint).length == 0) ? inferred[index] : original[index];
			}
		];
	}

	function checkedResult(declaration:TyDeclarationInfo, includeInputs:Bool):TyType {
		final written = declaration.getSignature().getReturnType();
		if (!written.isUnknown() && !includeInputs)
			return written;
		final source = declaration.getSourceDeclaration();
		if (source == null || !HxFunctionDecl.getHasBody(source))
			return written;
		final key = declaration.getIdentity().getCanonicalKey();
		final fingerprint = sourceFingerprint(source);
		final existing = checked.get(key);
		if (existing != null) {
			if (existing.declaration != declaration || existing.fingerprint != fingerprint)
				throw "method body result belongs to a changed declaration";
			recordAssumptions(existing.assumptions);
			return existing.type;
		}
		final pending = active.get(key);
		if (pending != null) {
			pending.recursive = true;
			recordAssumptions([key]);
			return pending.type;
		}
		if (infer == null)
			return written;
		final prior = [for (name in checked.keys()) name];
		function discardCandidateDependents():Void {
			for (name in [for (entry in checked.keys()) entry])
				if (prior.indexOf(name) < 0 && checked.get(name).assumptions.indexOf(key) >= 0)
					checked.remove(name);
		}
		var candidate = written;
		var candidateParameters = declaration.getSignature().getArgs();
		function identity(type:TyType, arguments:Array<TyType>):String {
			return CompilerCacheIdentity.encode([type.getSemanticKey()].concat(arguments.map(argument -> argument.getSemanticKey())));
		}
		final seen = new haxe.ds.StringMap<Bool>();
		while (true) {
			final frame:MethodResultFrame = {
				type: candidate,
				parameters: candidateParameters,
				assumptions: new haxe.ds.StringMap(),
				recursive: false
			};
			active.set(key, frame);
			final selected = try {
				infer(declaration);
			} catch (error:haxe.Exception) {
				active.remove(key);
				discardCandidateDependents();
				throw error;
			}
			active.remove(key);
			final selectedType = written.isUnknown() ? selected.type : written;
			final selectedParameters = parameters(declaration, selected.parameters);
			final selectedIdentity = identity(selectedType, selectedParameters);
			if ((!written.isUnknown() || selected.complete)
				&& !selectedType.hasUnknownComponent()
				&& (!frame.recursive || selectedIdentity == identity(candidate, candidateParameters))) {
				checked.set(key, {
					declaration: declaration,
					fingerprint: fingerprint,
					type: selectedType,
					parameters: selectedParameters,
					// This candidate converged and has left active. Retain only unfinished outer assumptions.
					assumptions: [for (name in frame.assumptions.keys()) if (active.exists(name)) name]
				});
				return selectedType;
			}
			// Reject facts that consumed this candidate; unrelated completed helpers remain valid.
			discardCandidateDependents();
			if (selectedType.hasUnknownComponent() || (!selected.complete && selectedType.isDynamic()) || seen.exists(selectedIdentity))
				return TyType.unknown();
			seen.set(selectedIdentity, true);
			candidate = selectedType;
			candidateParameters = selectedParameters;
		}
	}

	/**
		Recompute exact source identity on every lookup because parsed arrays remain mutable.
		Compact hashes can collide after an edit and must not authorize checked body facts.
		Input hints and omission rules belong to the identity alongside the executable body.
	 */
	static function sourceFingerprint(source:HxFunctionDecl):String {
		return CompilerCacheIdentity.encode([
			TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(source)),
			HxFunctionDecl.getReturnTypeHint(source),
			CompilerCacheIdentity.encode(HxFunctionDecl.getMetadata(source)),
			TypedFunctionDefault.sourceIdentity(HxFunctionDecl.getArgs(source))
		]);
	}

	/** Copy checked inputs and result; the original signature remains the declaration lookup key. */
	public function signature(declaration:TyDeclarationInfo):TyFunSig {
		final source = declaration.getSignature();
		final selected = checkedResult(declaration, source.getArgs().filter(argument -> argument.isUnknown()).length > 0);
		final key = declaration.getIdentity().getCanonicalKey();
		final existing = checked.get(key);
		final pending = active.get(key);
		final inputs = existing != null ? existing.parameters : pending != null ? pending.parameters : source.getArgs();
		if (selected.getSemanticKey() == source.getReturnType().getSemanticKey()
			&& CompilerCacheIdentity.encode(inputs.map(argument -> argument.getSemanticKey())) == CompilerCacheIdentity.encode(source.getArgs()
				.map(argument -> argument.getSemanticKey())))
			return source;
		return new TyFunSig(source.getName(), source.getIsStatic(), source.getArgNames(), inputs.copy(), source.getArgOptional(), source.getArgRest(),
			selected, source.getPos());
	}
}
