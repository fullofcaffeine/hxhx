import haxe.ds.StringMap;
import TyLocalDeclarationKind.TyLocalDeclarationKindTools;

/** Resolved signature inputs; the environment allocates each binding under the supplied function identity. */
typedef TyNestedFunctionEnvInput = {
	final identity:TyNestedFunctionId;
	final name:String;
	final parameters:Array<{final name:String; final type:TyType;}>;
	final typeParameterNames:Array<String>;
	final returnType:TyType;
	final returnExprType:TyType;
}

/**
	Function-local inference environment with deterministic lexical identities.

	`locals` is the declaration catalog in source traversal order. `scopes`
	contains only declarations currently visible at the traversal point, so a
	read selects the nearest active declaration instead of the first matching
	name anywhere in the function.

	The typer records the catalog once. Typed-body construction uses
	`createBodyReplay()` to traverse the same source structure, consume the
	recorded declarations in order, and freeze each selected symbol as an
	immutable `TyLocalBinding`.
**/
class TyFunctionEnv {
	final name:String;
	final ownerIdentity:String;
	final params:Array<TySymbol>;
	final locals:Array<TySymbol>;
	final scopes:Array<Array<TySymbol>>;
	final returnType:TyType;
	final returnExprType:TyType;
	final staticContext:Bool;
	final typeParameters:Array<TyTypeParameterId>;
	final enclosingSymbols:Array<TySymbol> = [];
	final replayMode:Bool;
	var replayCursor:Int;
	final controlScope:Null<TyControlScope>;
	final inference:TyFunctionInference;
	var untypedContext:Bool = false;

	/** Untyped permission belongs to the current expression traversal, not the whole function. */
	public function isUntypedContext():Bool
		return untypedContext;

	/** Restore lexical permission on success and on every compiler diagnostic. */
	public function withUntyped<T>(action:() -> T):T {
		final previous = untypedContext;
		untypedContext = true;
		try {
			final result = action();
			untypedContext = previous;
			return result;
		} catch (error:Dynamic) {
			// Haxe can throw values of any type. This cleanup boundary does not
			// inspect or convert the payload; it restores state and rethrows it.
			untypedContext = previous;
			throw error;
		}
	}

	public function new(name:String, params:Array<TySymbol>, locals:Array<TySymbol>, returnType:TyType, returnExprType:TyType, ?ownerIdentity:String,
			?activeScopes:Array<Array<TySymbol>>, replayMode:Bool = false, replayCursor:Int = 0, staticContext:Bool = false, ?controlScope:TyControlScope,
			?inference:TyFunctionInference, ?typeParameters:Array<TyTypeParameterId>) {
		this.name = name == null ? "" : name;
		this.ownerIdentity = ownerIdentity == null || ownerIdentity.length == 0 ? this.name : ownerIdentity;
		this.params = params == null ? [] : params.copy();
		this.locals = locals == null ? [] : locals.copy();
		this.returnType = returnType == null ? TyType.unknown() : returnType;
		this.returnExprType = returnExprType == null ? TyType.unknown() : returnExprType;
		this.staticContext = staticContext;
		this.typeParameters = typeParameters == null ? [] : typeParameters.copy();
		this.replayMode = replayMode;
		this.replayCursor = replayCursor;
		this.controlScope = controlScope;
		this.inference = inference == null ? new TyFunctionInference(this.ownerIdentity) : inference;
		this.scopes = new Array<Array<TySymbol>>();
		if (activeScopes == null) {
			this.scopes.push(this.locals.copy());
		} else {
			for (scope in activeScopes)
				this.scopes.push(scope == null ? [] : scope.copy());
		}
		if (this.scopes.length == 0)
			this.scopes.push([]);
	}

	public function getName():String
		return name;

	public function getOwnerIdentity():String
		return ownerIdentity;

	public function getInference():TyFunctionInference
		return inference;

	public function sealInference():Void
		inference.seal(params.concat(locals));

	public function getParams():Array<TySymbol>
		return params.copy();

	/** Every non-parameter declaration, including nested lambda and pattern bindings. **/
	public function getLocals():Array<TySymbol>
		return locals.copy();

	public function getReturnType():TyType
		return returnType;

	public function getReturnExprType():TyType
		return returnExprType;

	/** Report whether an unqualified member read occurs without an instance receiver. **/
	public function isStaticContext():Bool
		return staticContext;

	/** Generic declarations visible to local annotations, with nearer method parameters last. */
	public function getTypeParameters():Array<TyTypeParameterId>
		return typeParameters.copy();

	/**
		Start a separate function at the current lexical declaration point.

		Copy visibility, not inference slots: later outer declarations stay hidden,
		but refinements to an already visible symbol remain shared. Parameters and
		locals belong to the new function and shadow enclosing bindings. The visible
		set is not a capture-use list; typed body construction must record actual reads.
		A permitted recursive self declaration must already exist in the outer scope.
	**/
	public function createNestedFunction(input:TyNestedFunctionEnvInput):TyFunctionEnv {
		if (input.identity == null || input.identity.getOwnerIdentity() != ownerIdentity)
			throw "nested function identity does not belong to the enclosing function";
		final nestedOwner = input.identity.getCanonicalKey();
		final nestedParams = new Array<TySymbol>();
		for (index in 0...input.parameters.length) {
			final parameter = input.parameters[index];
			nestedParams.push(new TySymbol(parameter.name, parameter.type, TyLocalId.forSourceDeclaration(nestedOwner, index, Parameter, parameter.name),
				Parameter));
		}
		final generics = typeParameters.copy();
		for (index in 0...input.typeParameterNames.length)
			generics.push(TyTypeParameterId.nestedFunction(input.identity, index, input.typeParameterNames[index]));
		final nested = new TyFunctionEnv(input.name, nestedParams, [], input.returnType, input.returnExprType, nestedOwner, null, false, 0, staticContext,
			null, null, generics);
		nested.untypedContext = untypedContext;
		for (symbol in enclosingSymbols)
			nested.enclosingSymbols.push(symbol);
		for (parameter in params)
			nested.enclosingSymbols.push(parameter);
		for (scope in scopes)
			for (symbol in scope)
				nested.enclosingSymbols.push(symbol);
		return nested;
	}

	/** Preserve definition-time visibility when deriving a replay or sealed return environment. */
	function withEnclosingSymbolsFrom(source:TyFunctionEnv):TyFunctionEnv {
		untypedContext = source.untypedContext;
		for (symbol in source.enclosingSymbols)
			enclosingSymbols.push(symbol);
		return this;
	}

	/** Preserve the exact symbol catalog and active scopes while sealing return facts. **/
	public function withReturnTypes(finalReturnType:TyType, finalReturnExprType:TyType):TyFunctionEnv
		return new TyFunctionEnv(name, params, locals, finalReturnType, finalReturnExprType, ownerIdentity, scopes, replayMode, replayCursor, staticContext,
			controlScope == null ? null : controlScope.copy(), inference, typeParameters).withEnclosingSymbolsFrom(this);

	/** Source control requires a catalog tied to the current owning function revision. */
	public function requireControlScope():TyControlScope {
		if (controlScope == null)
			throw "source control requires a revision-owned function environment";
		return controlScope;
	}

	/** Synthetic declaration-only environments do not establish an executing source function. */
	public function getRootControlTarget():Null<TyControlTarget>
		return controlScope == null ? null : controlScope.getRoot();

	/** Expression-syntax probes can lack an executing source function. */
	public function currentSourceReturns():Null<TyFunctionReturnState>
		return controlScope == null ? null : controlScope.currentReturns();

	/** Begin a nested source scope. **/
	public function enterLexicalScope():Void
		scopes.push([]);

	/** End the nearest source scope without removing its declarations from the catalog. **/
	public function exitLexicalScope():Void {
		if (scopes.length <= 1)
			throw "cannot exit the root function-local scope";
		scopes.pop();
	}

	/**
		Declare or replay one local in deterministic source traversal order.

		In the typer pass this allocates the identity and appends it to the
		function catalog. In typed-body replay it consumes the corresponding
		already-typed symbol and fails if the two traversals disagree.
	**/
	public function declareLocal(name:String, ty:TyType, kind:TyLocalDeclarationKind = Variable):TySymbol {
		if (replayMode)
			return replayLocal(name, kind);
		final symbol = new TySymbol(name, ty, TyLocalId.forSourceDeclaration(ownerIdentity, params.length + locals.length, kind, name), kind);
		locals.push(symbol);
		scopes[scopes.length - 1].push(symbol);
		return symbol;
	}

	function replayLocal(name:String, kind:TyLocalDeclarationKind):TySymbol {
		if (replayCursor >= locals.length)
			throw "typed local declaration replay produced more declarations than typing for " + ownerIdentity;
		final symbol = locals[replayCursor++];
		if (symbol.getName() != (name == null ? "" : name) || symbol.getKind() != kind)
			throw "typed local declaration replay mismatch for "
				+ ownerIdentity
				+ ": expected "
				+ TyLocalDeclarationKindTools.canonicalName(kind)
				+ " "
				+ name
				+ " but typing recorded "
				+ TyLocalDeclarationKindTools.canonicalName(symbol.getKind())
				+ " "
				+ symbol.getName();
		scopes[scopes.length - 1].push(symbol);
		return symbol;
	}

	/** Resolve locals, then parameters, then the enclosing bindings visible at definition time. **/
	public function resolveSymbol(name:String):Null<TySymbol> {
		var scopeIndex = scopes.length;
		while (scopeIndex > 0) {
			scopeIndex--;
			final scope = scopes[scopeIndex];
			var symbolIndex = scope.length;
			while (symbolIndex > 0) {
				symbolIndex--;
				final symbol = scope[symbolIndex];
				if (symbol.getName() == name)
					return symbol;
			}
		}
		var parameterIndex = params.length;
		while (parameterIndex > 0) {
			parameterIndex--;
			final parameter = params[parameterIndex];
			if (parameter.getName() == name)
				return parameter;
		}
		var enclosingIndex = enclosingSymbols.length;
		while (enclosingIndex > 0) {
			final symbol = enclosingSymbols[--enclosingIndex];
			if (symbol.getName() == name)
				return symbol;
		}
		return null;
	}

	public function resolveLocal(name:String):TyType {
		final symbol = resolveSymbol(name);
		return symbol == null ? TyType.unknown() : symbol.getType();
	}

	/**
		Create the lexical replay used to build immutable typed nodes.

		Parameters begin visible; ordinary locals become visible only when their
		source declaration is encountered during the second traversal.
	**/
	public function createBodyReplay():TyFunctionEnv
		return new TyFunctionEnv(name, params, locals, returnType, returnExprType, ownerIdentity, [[]], true, 0, staticContext,
			controlScope == null ? null : controlScope.createReplay(), inference, typeParameters).withEnclosingSymbolsFrom(this);

	/** Reject a builder traversal that silently skipped typed declarations. **/
	public function assertReplayComplete():Void {
		if (!replayMode)
			throw "typed local replay completion checked outside replay mode";
		if (replayCursor != locals.length)
			throw "typed local declaration replay consumed "
				+ replayCursor
				+ " of "
				+ locals.length
				+ " declarations for "
				+ ownerIdentity;
		if (scopes.length != 1)
			throw "typed local declaration replay left nested scopes open for " + ownerIdentity;
		if (controlScope != null)
			controlScope.assertReplayComplete();
	}

	/**
		Create an isolated snapshot for speculative expression inference.

		The copy preserves exact identities, active lexical scopes, and replay
		position while giving every symbol its own mutable type slot.
	**/
	public function copyForInference():TyFunctionEnv {
		final copies = new StringMap<TySymbol>();
		function copySymbol(symbol:TySymbol):TySymbol {
			final key = symbol.getIdentity().getCanonicalKey();
			final existing = copies.get(key);
			if (existing != null)
				return existing;
			final copied = new TySymbol(symbol.getName(), symbol.getType(), symbol.getIdentity(), symbol.getKind());
			copies.set(key, copied);
			return copied;
		}
		final copiedParams = [for (parameter in params) copySymbol(parameter)];
		final copiedLocals = [for (local in locals) copySymbol(local)];
		final copiedScopes = [for (scope in scopes) [for (symbol in scope) copySymbol(symbol)]];
		// Speculative resolvers may introduce desugared lambda temporaries that are
		// not declarations in the sealed source traversal. They must allocate only
		// inside this copy instead of consuming the typed-body replay catalog.
		final copied = new TyFunctionEnv(name, copiedParams, copiedLocals, returnType, returnExprType, ownerIdentity, copiedScopes, false, 0, staticContext,
			controlScope == null ? null : controlScope.copyForInference(), inference.fork(), typeParameters);
		copied.untypedContext = untypedContext;
		for (symbol in enclosingSymbols)
			copied.enclosingSymbols.push(copySymbol(symbol));
		return copied;
	}
}
