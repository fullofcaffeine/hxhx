import haxe.ds.StringMap;
import TyLocalDeclarationKind.TyLocalDeclarationKindTools;

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
	final replayMode:Bool;
	var replayCursor:Int;

	public function new(name:String, params:Array<TySymbol>, locals:Array<TySymbol>, returnType:TyType, returnExprType:TyType, ?ownerIdentity:String,
			?activeScopes:Array<Array<TySymbol>>, replayMode:Bool = false, replayCursor:Int = 0, staticContext:Bool = false) {
		this.name = name == null ? "" : name;
		this.ownerIdentity = ownerIdentity == null || ownerIdentity.length == 0 ? this.name : ownerIdentity;
		this.params = params == null ? [] : params.copy();
		this.locals = locals == null ? [] : locals.copy();
		this.returnType = returnType == null ? TyType.unknown() : returnType;
		this.returnExprType = returnExprType == null ? TyType.unknown() : returnExprType;
		this.staticContext = staticContext;
		this.replayMode = replayMode;
		this.replayCursor = replayCursor;
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

	/** Preserve the exact symbol catalog and active scopes while sealing return facts. **/
	public function withReturnTypes(finalReturnType:TyType, finalReturnExprType:TyType):TyFunctionEnv
		return new TyFunctionEnv(name, params, locals, finalReturnType, finalReturnExprType, ownerIdentity, scopes, replayMode, replayCursor, staticContext);

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

	/** Resolve the nearest active local, falling back to function parameters. **/
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
		return new TyFunctionEnv(name, params, locals, returnType, returnExprType, ownerIdentity, [[]], true, 0, staticContext);

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
		return new TyFunctionEnv(name, copiedParams, copiedLocals, returnType, returnExprType, ownerIdentity, copiedScopes, false, 0, staticContext);
	}
}
