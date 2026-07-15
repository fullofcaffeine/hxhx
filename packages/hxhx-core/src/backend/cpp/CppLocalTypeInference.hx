package backend.cpp;

import haxe.ds.StringMap;

typedef CppLocalTypeInferenceApi = {
	var copyStringMap:StringMap<String>->StringMap<String>;
	var copyIntMap:StringMap<Int>->StringMap<Int>;
	var sanitizeIdentifier:String->String;
	var sanitizeTypePath:String->String;
	var typeBaseName:String->String;
	var isInferredMapClassName:String->Bool;
	var exprCppType:(HxExpr, CppRenderScope) -> String;
	var inferExprCppType:(HxExpr, CppRenderScope) -> String;
	var isStringLike:HxExpr->Bool;
	var isDynamicLikeTypeHint:String->Bool;
	var dynamicLocalAssignedType:(HxExpr, CppRenderScope) -> String;
	var anonStructName:(Array<String>, Array<HxExpr>, CppRenderScope) -> String;
	var inferredLambdaCppFunctionType:(Array<String>, HxExpr, Array<String>, CppRenderScope) -> String;
	var closureCallableArgType:(HxExpr, CppRenderScope) -> String;
	var localCppName:(String, CppRenderScope) -> String;
	var declareLocalName:(String, CppRenderScope) -> String;
	var cppLocalTypeHint:(String, Null<HxExpr>, CppRenderScope) -> String;
	var cppTypeHint:(String, CppRenderScope) -> String;
	var staticReceiverClassName:(HxExpr, CppRenderScope) -> Null<String>;
	var isEnumCarrierClassName:(String, CppRenderScope) -> Bool;
	var hasStaticEnumConstructorMethod:(String, String, CppRenderScope) -> Bool;
	var hasStaticEnumMetadataField:(String, String, CppRenderScope) -> Bool;
	var arrowMapLiteralCppType:(HxExpr, CppRenderScope) -> String;
	var iterableElementType:(HxExpr, CppRenderScope) -> String;
	var keyValueLoopTypes:(HxExpr, CppRenderScope) -> Array<String>;
	var withScopedLocal:(CppRenderScope, String, String, Void->Void) -> Void;
}

/**
	C++ local type inference passes that run before source rendering.

	`CppTargetCore` owns emission. This module owns focused pre-render inference
	traversals that refine local type overrides without writing C++ source. This
	includes key/value carriers already present in arrow-map literals. Keep
	new local/arg/return flow passes here when they are reusable analysis over
	`HxStmt`/`HxExpr`; leave target-specific rendering decisions in
	`CppTargetCore`.
**/
class CppLocalTypeInference {
	final api:CppLocalTypeInferenceApi;

	function new(api:CppLocalTypeInferenceApi) {
		this.api = api;
	}

	public static function inferStringMapLocalTypeOverrides(scope:CppRenderScope, fn:HxFunctionDecl, api:CppLocalTypeInferenceApi):Void {
		if (scope == null || fn == null)
			return;
		new CppLocalTypeInference(api).inferStringMapLocalTypeOverridesFromStmtsImpl(scope, HxFunctionDecl.getBody(fn));
	}

	public static function inferStringMapLocalTypeOverridesFromStmts(scope:CppRenderScope, stmts:Array<HxStmt>, api:CppLocalTypeInferenceApi):Void {
		if (scope == null || stmts == null)
			return;
		new CppLocalTypeInference(api).inferStringMapLocalTypeOverridesFromStmtsImpl(scope, stmts);
	}

	public static function inferClosureVectorLocalTypeOverrides(scope:CppRenderScope, fn:HxFunctionDecl, api:CppLocalTypeInferenceApi):Void {
		if (scope == null || fn == null)
			return;
		new CppLocalTypeInference(api).inferClosureVectorLocalTypeOverridesImpl(scope, HxFunctionDecl.getBody(fn));
	}

	public static function closureVectorTypeForLambdaArg(local:String, body:HxExpr, scope:CppRenderScope, api:CppLocalTypeInferenceApi):String {
		if (scope == null || local == null || local.length == 0)
			return "";
		return new CppLocalTypeInference(api).closureVectorTypeForLambdaArgImpl(local, body, scope);
	}

	/**
		Recover the C++ carrier type of a qualified enum constructor expression.

		Parsed enum constructor helpers retain their source-level `String` return
		hint even though C++ emits metadata-preserving `shared_ptr` values. This
		narrow analysis recognizes only qualified constructors owned by a known enum
		carrier. Local declarations and map-literal pair selection share this answer;
		ordinary String and reference factories keep using general expression
		inference.
	**/
	public static function qualifiedEnumCarrierCppType(expr:Null<HxExpr>, scope:CppRenderScope, api:CppLocalTypeInferenceApi):String {
		if (expr == null || scope == null)
			return "";
		return qualifiedEnumCarrierCppTypeImpl(expr, scope, api);
	}

	static function qualifiedEnumCarrierCppTypeImpl(expr:HxExpr, scope:CppRenderScope, api:CppLocalTypeInferenceApi):String {
		return switch (expr) {
			case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				qualifiedEnumCarrierCppTypeImpl(inner, scope, api);
			case ECall(EField(receiver, constructorName), args) if (args != null && args.length > 0):
				final owner = api.staticReceiverClassName(receiver, scope);
				if (owner != null
					&& api.isEnumCarrierClassName(owner, scope)
					&& api.hasStaticEnumConstructorMethod(owner, constructorName, scope)) api.cppTypeHint(owner, scope); else "";
			case EField(receiver, constructorName):
				final owner = api.staticReceiverClassName(receiver, scope);
				if (owner != null
					&& api.isEnumCarrierClassName(owner, scope)
					&& api.hasStaticEnumMetadataField(owner, constructorName, scope)) api.cppTypeHint(owner, scope); else "";
			case _:
				"";
		};
	}

	/**
		Return declared `Dynamic` arguments used through erased-value operations.

		The C++ backend still has legacy string-shaped Dynamic helper surfaces. This
		analysis only identifies arguments whose bodies require erased carriers, such
		as equality, switch scrutinees, `Std.isOfType` values, or `Type.typeof`
		probes.
	**/
	public static function erasedDynamicArgUsageNames(args:Array<HxFunctionArg>, body:Array<HxStmt>, candidates:StringMap<Bool>,
			api:CppLocalTypeInferenceApi):StringMap<Bool> {
		return new CppLocalTypeInference(api).erasedDynamicArgUsageNamesImpl(args, body, candidates);
	}

	function erasedDynamicArgUsageNamesImpl(args:Array<HxFunctionArg>, body:Array<HxStmt>, candidates:StringMap<Bool>):StringMap<Bool> {
		final dynamicArgs = new StringMap<Bool>();
		if (args != null)
			for (arg in args) {
				final name = api.sanitizeIdentifier(HxFunctionArg.getName(arg));
				if (candidates.exists(name) && api.isDynamicLikeTypeHint(HxFunctionArg.getTypeHint(arg)))
					dynamicArgs.set(name, true);
			}
		final used = new StringMap<Bool>();
		if (!boolMapHasEntries(dynamicArgs) || body == null)
			return used;
		for (stmt in body)
			collectErasedDynamicArgUsageNamesFromStmt(stmt, dynamicArgs, used);
		return used;
	}

	function collectErasedDynamicArgUsageNamesFromStmt(stmt:HxStmt, dynamicArgs:StringMap<Bool>, used:StringMap<Bool>):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectErasedDynamicArgUsageNamesFromStmt(s, dynamicArgs, used);
			case SIf(cond, thenBranch, elseBranch, _):
				collectErasedDynamicArgUsageNamesFromExpr(cond, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromStmt(thenBranch, dynamicArgs, used);
				if (elseBranch != null)
					collectErasedDynamicArgUsageNamesFromStmt(elseBranch, dynamicArgs, used);
			case SForIn(_, iterable, body, _) | SForKeyValue(_, _, iterable, body, _):
				collectErasedDynamicArgUsageNamesFromExpr(iterable, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromStmt(body, dynamicArgs, used);
			case SWhile(cond, body, _) | SDoWhile(body, cond, _):
				collectErasedDynamicArgUsageNamesFromExpr(cond, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromStmt(body, dynamicArgs, used);
			case SSwitch(scrutinee, _, bodies, _):
				collectErasedDynamicArgUsageNamesFromExpr(scrutinee, dynamicArgs, used);
				for (body in bodies)
					collectErasedDynamicArgUsageNamesFromStmt(body, dynamicArgs, used);
			case STry(tryBody, catches, _):
				collectErasedDynamicArgUsageNamesFromStmt(tryBody, dynamicArgs, used);
				for (c in catches)
					collectErasedDynamicArgUsageNamesFromStmt(c.body, dynamicArgs, used);
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				collectErasedDynamicArgUsageNamesFromExpr(expr, dynamicArgs, used);
			case SVar(_, _, init, _):
				if (init != null)
					collectErasedDynamicArgUsageNamesFromExpr(init, dynamicArgs, used);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	function collectErasedDynamicArgUsageNamesFromExpr(expr:HxExpr, dynamicArgs:StringMap<Bool>, used:StringMap<Bool>):Void {
		switch (expr) {
			case EBinop(op, left, right) if (op == "==" || op == "!="):
				markErasedDynamicArgIdent(left, dynamicArgs, used);
				markErasedDynamicArgIdent(right, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromExpr(left, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromExpr(right, dynamicArgs, used);
			case ESwitch(scrutinee, _, exprs):
				markErasedDynamicArgIdent(scrutinee, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromExpr(scrutinee, dynamicArgs, used);
				for (value in exprs)
					collectErasedDynamicArgUsageNamesFromExpr(value, dynamicArgs, used);
			case ECall(EField(EIdent("Std"), method), args) if ((method == "isOfType" || method == "is") && args.length > 0):
				markErasedDynamicArgIdent(args[0], dynamicArgs, used);
				for (arg in args)
					collectErasedDynamicArgUsageNamesFromExpr(arg, dynamicArgs, used);
			case ECall(EField(EIdent("Type"), "typeof"), args) if (args.length > 0):
				markErasedDynamicArgIdent(args[0], dynamicArgs, used);
				for (arg in args)
					collectErasedDynamicArgUsageNamesFromExpr(arg, dynamicArgs, used);
			case EBinop(_, left, right):
				collectErasedDynamicArgUsageNamesFromExpr(left, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromExpr(right, dynamicArgs, used);
			case ECall(callee, args):
				collectErasedDynamicArgUsageNamesFromExpr(callee, dynamicArgs, used);
				for (arg in args)
					collectErasedDynamicArgUsageNamesFromExpr(arg, dynamicArgs, used);
			case EArrayAccess(array, index):
				collectErasedDynamicArgUsageNamesFromExpr(array, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromExpr(index, dynamicArgs, used);
			case EField(receiver, _):
				collectErasedDynamicArgUsageNamesFromExpr(receiver, dynamicArgs, used);
			case EArrayDecl(elements):
				for (element in elements)
					collectErasedDynamicArgUsageNamesFromExpr(element, dynamicArgs, used);
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr):
				collectErasedDynamicArgUsageNamesFromExpr(iterable, dynamicArgs, used);
				if (guardExpr != null)
					collectErasedDynamicArgUsageNamesFromExpr(guardExpr, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromExpr(yieldExpr, dynamicArgs, used);
			case EUnop(_, _, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				collectErasedDynamicArgUsageNamesFromExpr(inner, dynamicArgs, used);
			case ETernary(cond, thenExpr, elseExpr):
				collectErasedDynamicArgUsageNamesFromExpr(cond, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromExpr(thenExpr, dynamicArgs, used);
				collectErasedDynamicArgUsageNamesFromExpr(elseExpr, dynamicArgs, used);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectErasedDynamicArgUsageNamesFromExpr(value, dynamicArgs, used);
			case ELambda(_, body):
				collectErasedDynamicArgUsageNamesFromExpr(body, dynamicArgs, used);
			case ENew(_, args):
				for (arg in args)
					collectErasedDynamicArgUsageNamesFromExpr(arg, dynamicArgs, used);
			case _:
		}
	}

	function markErasedDynamicArgIdent(expr:HxExpr, dynamicArgs:StringMap<Bool>, used:StringMap<Bool>):Void {
		switch (expr) {
			case EIdent(name):
				final local = api.sanitizeIdentifier(name);
				if (dynamicArgs.exists(local))
					used.set(local, true);
			case _:
		}
	}

	function inferClosureVectorLocalTypeOverridesImpl(scope:CppRenderScope, stmts:Array<HxStmt>):Void {
		final candidates = new StringMap<Bool>();
		for (stmt in stmts)
			collectClosureVectorLocalCandidatesFromStmt(stmt, candidates);
		if (!boolMapHasEntries(candidates))
			return;
		final savedLocalTypes = copyStringMap(scope.localTypes);
		final savedLocalNames = copyStringMap(scope.localNames);
		final savedLocalNameCounts = copyIntMap(scope.localNameCounts);
		final savedLocalTypeOverrides = copyStringMap(scope.localTypeOverrides);
		function restoreScope():Void {
			scope.localTypes = copyStringMap(savedLocalTypes);
			scope.localNames = copyStringMap(savedLocalNames);
			scope.localNameCounts = copyIntMap(savedLocalNameCounts);
			scope.localTypeOverrides = copyStringMap(savedLocalTypeOverrides);
		}
		final pushedValues = new StringMap<Array<HxExpr>>();
		final callArgTypes = new StringMap<Array<Array<String>>>();
		final inferredVectors = new StringMap<String>();
		for (stmt in stmts)
			collectClosureVectorEvidenceFromStmt(stmt, scope, candidates, pushedValues, callArgTypes);
		restoreScope();
		final pushedTypes = new StringMap<Array<String>>();
		for (stmt in stmts)
			collectClosureVectorPushedTypesFromStmt(stmt, scope, candidates, callArgTypes, pushedTypes);
		for (local in pushedTypes.keys()) {
			final elementType = firstNonEmptyType(pushedTypes.get(local));
			if (elementType.length > 0)
				inferredVectors.set(local, "std::vector<" + elementType + ">");
		}
		restoreScope();
		for (local in inferredVectors.keys()) {
			final inferred = inferredVectors.get(local);
			final existing = scope.localTypeOverrides.get(local);
			if (existing == null || existing.length == 0 || existing == inferred)
				scope.localTypeOverrides.set(local, inferred);
		}
	}

	function collectClosureVectorLocalCandidatesFromStmt(stmt:HxStmt, candidates:StringMap<Bool>):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectClosureVectorLocalCandidatesFromStmt(s, candidates);
			case SIf(_, thenBranch, elseBranch, _):
				collectClosureVectorLocalCandidatesFromStmt(thenBranch, candidates);
				if (elseBranch != null)
					collectClosureVectorLocalCandidatesFromStmt(elseBranch, candidates);
			case SForIn(_, _, body, _) | SWhile(_, body, _) | SDoWhile(body, _, _):
				collectClosureVectorLocalCandidatesFromStmt(body, candidates);
			case SForKeyValue(_, _, _, body, _):
				collectClosureVectorLocalCandidatesFromStmt(body, candidates);
			case SSwitch(_, _, bodies, _):
				for (body in bodies)
					collectClosureVectorLocalCandidatesFromStmt(body, candidates);
			case STry(tryBody, catches, _):
				collectClosureVectorLocalCandidatesFromStmt(tryBody, candidates);
				for (c in catches)
					collectClosureVectorLocalCandidatesFromStmt(c.body, candidates);
			case SVar(name, typeHint, init, _) if (isUnhintedEmptyArray(typeHint, init)):
				candidates.set(sanitizeIdentifier(name), true);
			case SExpr(EBinop("=", EIdent(name), init), _) if (isEmptyArrayExpr(init)):
				candidates.set(sanitizeIdentifier(name), true);
			case SVar(_, _, _, _) | SExpr(_, _) | SReturn(_, _) | SThrow(_, _) | SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	function collectClosureVectorEvidenceFromStmt(stmt:HxStmt, scope:CppRenderScope, candidates:StringMap<Bool>, pushedValues:StringMap<Array<HxExpr>>,
			callArgTypes:StringMap<Array<Array<String>>>):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectClosureVectorEvidenceFromStmt(s, scope, candidates, pushedValues, callArgTypes);
			case SIf(cond, thenBranch, elseBranch, _):
				collectClosureVectorEvidenceFromExpr(cond, scope, candidates, pushedValues, callArgTypes);
				collectClosureVectorEvidenceFromStmt(thenBranch, scope, candidates, pushedValues, callArgTypes);
				if (elseBranch != null)
					collectClosureVectorEvidenceFromStmt(elseBranch, scope, candidates, pushedValues, callArgTypes);
			case SForIn(name, iterable, body, _):
				collectClosureVectorEvidenceFromExpr(iterable, scope, candidates, pushedValues, callArgTypes);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					collectClosureVectorEvidenceFromStmt(body, scope, candidates, pushedValues, callArgTypes);
				});
			case SForKeyValue(keyName, valueName, iterable, body, _):
				collectClosureVectorEvidenceFromExpr(iterable, scope, candidates, pushedValues, callArgTypes);
				final loopTypes = keyValueLoopTypes(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(keyName), loopTypes[0], () -> {
					withScopedLocal(scope, sanitizeIdentifier(valueName), loopTypes[1], () -> {
						collectClosureVectorEvidenceFromStmt(body, scope, candidates, pushedValues, callArgTypes);
					});
				});
			case SWhile(cond, body, _):
				collectClosureVectorEvidenceFromExpr(cond, scope, candidates, pushedValues, callArgTypes);
				collectClosureVectorEvidenceFromStmt(body, scope, candidates, pushedValues, callArgTypes);
			case SDoWhile(body, cond, _):
				collectClosureVectorEvidenceFromStmt(body, scope, candidates, pushedValues, callArgTypes);
				collectClosureVectorEvidenceFromExpr(cond, scope, candidates, pushedValues, callArgTypes);
			case SSwitch(scrutinee, _, bodies, _):
				collectClosureVectorEvidenceFromExpr(scrutinee, scope, candidates, pushedValues, callArgTypes);
				for (body in bodies)
					collectClosureVectorEvidenceFromStmt(body, scope, candidates, pushedValues, callArgTypes);
			case STry(tryBody, catches, _):
				collectClosureVectorEvidenceFromStmt(tryBody, scope, candidates, pushedValues, callArgTypes);
				for (c in catches)
					collectClosureVectorEvidenceFromStmt(c.body, scope, candidates, pushedValues, callArgTypes);
			case SVar(name, typeHint, init, _):
				if (init != null)
					collectClosureVectorEvidenceFromExpr(init, scope, candidates, pushedValues, callArgTypes);
				final local = sanitizeIdentifier(name);
				if (!candidates.exists(local) || !isUnhintedEmptyArray(typeHint, init)) {
					final localType = cppLocalTypeHint(typeHint, init, scope);
					if (localType.length > 0)
						scope.localTypes.set(local, localType);
				}
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				collectClosureVectorEvidenceFromExpr(expr, scope, candidates, pushedValues, callArgTypes);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	function collectClosureVectorEvidenceFromExpr(expr:HxExpr, scope:CppRenderScope, candidates:StringMap<Bool>, pushedValues:StringMap<Array<HxExpr>>,
			callArgTypes:StringMap<Array<Array<String>>>):Void {
		switch (expr) {
			case ECall(EField(EIdent(name), "push"), [value]) if (candidates.exists(sanitizeIdentifier(name))):
				final local = sanitizeIdentifier(name);
				if (!pushedValues.exists(local))
					pushedValues.set(local, []);
				pushedValues.get(local).push(value);
				collectClosureVectorEvidenceFromExpr(value, scope, candidates, pushedValues, callArgTypes);
			case ECall(EArrayAccess(EIdent(name), index), args) if (candidates.exists(sanitizeIdentifier(name))):
				final local = sanitizeIdentifier(name);
				if (!callArgTypes.exists(local))
					callArgTypes.set(local, []);
				callArgTypes.get(local).push([for (arg in args) closureCallableArgType(arg, scope)]);
				collectClosureVectorEvidenceFromExpr(index, scope, candidates, pushedValues, callArgTypes);
				for (arg in args)
					collectClosureVectorEvidenceFromExpr(arg, scope, candidates, pushedValues, callArgTypes);
			case EBinop(_, left, right):
				collectClosureVectorEvidenceFromExpr(left, scope, candidates, pushedValues, callArgTypes);
				collectClosureVectorEvidenceFromExpr(right, scope, candidates, pushedValues, callArgTypes);
			case ECall(callee, args):
				collectClosureVectorEvidenceFromExpr(callee, scope, candidates, pushedValues, callArgTypes);
				for (arg in args)
					collectClosureVectorEvidenceFromExpr(arg, scope, candidates, pushedValues, callArgTypes);
			case EArrayAccess(array, index):
				collectClosureVectorEvidenceFromExpr(array, scope, candidates, pushedValues, callArgTypes);
				collectClosureVectorEvidenceFromExpr(index, scope, candidates, pushedValues, callArgTypes);
			case EField(receiver, _):
				collectClosureVectorEvidenceFromExpr(receiver, scope, candidates, pushedValues, callArgTypes);
			case EArrayDecl(elements):
				for (element in elements)
					collectClosureVectorEvidenceFromExpr(element, scope, candidates, pushedValues, callArgTypes);
			case EArrayComprehension(name, iterable, filter, body):
				collectClosureVectorEvidenceFromExpr(iterable, scope, candidates, pushedValues, callArgTypes);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					if (filter != null)
						collectClosureVectorEvidenceFromExpr(filter, scope, candidates, pushedValues, callArgTypes);
					collectClosureVectorEvidenceFromExpr(body, scope, candidates, pushedValues, callArgTypes);
				});
			case ERange(start, end):
				collectClosureVectorEvidenceFromExpr(start, scope, candidates, pushedValues, callArgTypes);
				collectClosureVectorEvidenceFromExpr(end, scope, candidates, pushedValues, callArgTypes);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectClosureVectorEvidenceFromExpr(value, scope, candidates, pushedValues, callArgTypes);
			case ESwitch(scrutinee, _, exprs):
				collectClosureVectorEvidenceFromExpr(scrutinee, scope, candidates, pushedValues, callArgTypes);
				for (value in exprs)
					collectClosureVectorEvidenceFromExpr(value, scope, candidates, pushedValues, callArgTypes);
			case ETernary(cond, thenExpr, elseExpr):
				collectClosureVectorEvidenceFromExpr(cond, scope, candidates, pushedValues, callArgTypes);
				collectClosureVectorEvidenceFromExpr(thenExpr, scope, candidates, pushedValues, callArgTypes);
				collectClosureVectorEvidenceFromExpr(elseExpr, scope, candidates, pushedValues, callArgTypes);
			case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _) | EUnop(_, _, inner) | ELambda(_, inner):
				collectClosureVectorEvidenceFromExpr(inner, scope, candidates, pushedValues, callArgTypes);
			case ENew(_, args):
				for (arg in args)
					collectClosureVectorEvidenceFromExpr(arg, scope, candidates, pushedValues, callArgTypes);
			case _:
		}
	}

	function collectClosureVectorPushedTypesFromStmt(stmt:HxStmt, scope:CppRenderScope, candidates:StringMap<Bool>,
			callArgTypes:StringMap<Array<Array<String>>>, pushedTypes:StringMap<Array<String>>):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					collectClosureVectorPushedTypesFromStmt(s, scope, candidates, callArgTypes, pushedTypes);
			case SIf(cond, thenBranch, elseBranch, _):
				collectClosureVectorPushedTypesFromExpr(cond, scope, candidates, callArgTypes, pushedTypes);
				collectClosureVectorPushedTypesFromStmt(thenBranch, scope, candidates, callArgTypes, pushedTypes);
				if (elseBranch != null)
					collectClosureVectorPushedTypesFromStmt(elseBranch, scope, candidates, callArgTypes, pushedTypes);
			case SForIn(name, iterable, body, _):
				collectClosureVectorPushedTypesFromExpr(iterable, scope, candidates, callArgTypes, pushedTypes);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					collectClosureVectorPushedTypesFromStmt(body, scope, candidates, callArgTypes, pushedTypes);
				});
			case SForKeyValue(keyName, valueName, iterable, body, _):
				collectClosureVectorPushedTypesFromExpr(iterable, scope, candidates, callArgTypes, pushedTypes);
				final loopTypes = keyValueLoopTypes(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(keyName), loopTypes[0], () -> {
					withScopedLocal(scope, sanitizeIdentifier(valueName), loopTypes[1], () -> {
						collectClosureVectorPushedTypesFromStmt(body, scope, candidates, callArgTypes, pushedTypes);
					});
				});
			case SWhile(cond, body, _):
				collectClosureVectorPushedTypesFromExpr(cond, scope, candidates, callArgTypes, pushedTypes);
				collectClosureVectorPushedTypesFromStmt(body, scope, candidates, callArgTypes, pushedTypes);
			case SDoWhile(body, cond, _):
				collectClosureVectorPushedTypesFromStmt(body, scope, candidates, callArgTypes, pushedTypes);
				collectClosureVectorPushedTypesFromExpr(cond, scope, candidates, callArgTypes, pushedTypes);
			case SSwitch(scrutinee, _, bodies, _):
				collectClosureVectorPushedTypesFromExpr(scrutinee, scope, candidates, callArgTypes, pushedTypes);
				for (body in bodies)
					collectClosureVectorPushedTypesFromStmt(body, scope, candidates, callArgTypes, pushedTypes);
			case STry(tryBody, catches, _):
				collectClosureVectorPushedTypesFromStmt(tryBody, scope, candidates, callArgTypes, pushedTypes);
				for (c in catches)
					collectClosureVectorPushedTypesFromStmt(c.body, scope, candidates, callArgTypes, pushedTypes);
			case SVar(name, typeHint, init, _):
				if (init != null)
					collectClosureVectorPushedTypesFromExpr(init, scope, candidates, callArgTypes, pushedTypes);
				final local = sanitizeIdentifier(name);
				if (!candidates.exists(local) || !isUnhintedEmptyArray(typeHint, init)) {
					final localType = cppLocalTypeHint(typeHint, init, scope);
					if (localType.length > 0)
						scope.localTypes.set(local, localType);
				}
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				collectClosureVectorPushedTypesFromExpr(expr, scope, candidates, callArgTypes, pushedTypes);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	function collectClosureVectorPushedTypesFromExpr(expr:HxExpr, scope:CppRenderScope, candidates:StringMap<Bool>,
			callArgTypes:StringMap<Array<Array<String>>>, pushedTypes:StringMap<Array<String>>):Void {
		switch (expr) {
			case ECall(EField(EIdent(name), "push"), [value]) if (candidates.exists(sanitizeIdentifier(name))):
				final local = sanitizeIdentifier(name);
				if (!pushedTypes.exists(local))
					pushedTypes.set(local, []);
				pushedTypes.get(local).push(closureVectorPushedValueType(value, callArgTypes.exists(local) ? callArgTypes.get(local) : [], scope));
				collectClosureVectorPushedTypesFromExpr(value, scope, candidates, callArgTypes, pushedTypes);
			case EBinop(_, left, right):
				collectClosureVectorPushedTypesFromExpr(left, scope, candidates, callArgTypes, pushedTypes);
				collectClosureVectorPushedTypesFromExpr(right, scope, candidates, callArgTypes, pushedTypes);
			case ECall(callee, args):
				collectClosureVectorPushedTypesFromExpr(callee, scope, candidates, callArgTypes, pushedTypes);
				for (arg in args)
					collectClosureVectorPushedTypesFromExpr(arg, scope, candidates, callArgTypes, pushedTypes);
			case EArrayAccess(array, index):
				collectClosureVectorPushedTypesFromExpr(array, scope, candidates, callArgTypes, pushedTypes);
				collectClosureVectorPushedTypesFromExpr(index, scope, candidates, callArgTypes, pushedTypes);
			case EField(receiver, _):
				collectClosureVectorPushedTypesFromExpr(receiver, scope, candidates, callArgTypes, pushedTypes);
			case EArrayDecl(elements):
				for (element in elements)
					collectClosureVectorPushedTypesFromExpr(element, scope, candidates, callArgTypes, pushedTypes);
			case EArrayComprehension(name, iterable, filter, body):
				collectClosureVectorPushedTypesFromExpr(iterable, scope, candidates, callArgTypes, pushedTypes);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					if (filter != null)
						collectClosureVectorPushedTypesFromExpr(filter, scope, candidates, callArgTypes, pushedTypes);
					collectClosureVectorPushedTypesFromExpr(body, scope, candidates, callArgTypes, pushedTypes);
				});
			case ERange(start, end):
				collectClosureVectorPushedTypesFromExpr(start, scope, candidates, callArgTypes, pushedTypes);
				collectClosureVectorPushedTypesFromExpr(end, scope, candidates, callArgTypes, pushedTypes);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectClosureVectorPushedTypesFromExpr(value, scope, candidates, callArgTypes, pushedTypes);
			case ESwitch(scrutinee, _, exprs):
				collectClosureVectorPushedTypesFromExpr(scrutinee, scope, candidates, callArgTypes, pushedTypes);
				for (value in exprs)
					collectClosureVectorPushedTypesFromExpr(value, scope, candidates, callArgTypes, pushedTypes);
			case ETernary(cond, thenExpr, elseExpr):
				collectClosureVectorPushedTypesFromExpr(cond, scope, candidates, callArgTypes, pushedTypes);
				collectClosureVectorPushedTypesFromExpr(thenExpr, scope, candidates, callArgTypes, pushedTypes);
				collectClosureVectorPushedTypesFromExpr(elseExpr, scope, candidates, callArgTypes, pushedTypes);
			case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _) | EUnop(_, _, inner) | ELambda(_, inner):
				collectClosureVectorPushedTypesFromExpr(inner, scope, candidates, callArgTypes, pushedTypes);
			case ENew(_, args):
				for (arg in args)
					collectClosureVectorPushedTypesFromExpr(arg, scope, candidates, callArgTypes, pushedTypes);
			case _:
		}
	}

	function closureVectorPushedValueType(value:HxExpr, callShapes:Array<Array<String>>, scope:CppRenderScope):String {
		return switch (value) {
			case ELambda(args, body):
				inferredLambdaCppFunctionType(args, body, closureVectorCallArgTypes(callShapes, args.length), scope);
			case ECall(EIdent("__hxhx_optional_lambda"), [ELambda(args, body), EArrayDecl(_)]):
				inferredLambdaCppFunctionType(args, body, closureVectorCallArgTypes(callShapes, args.length), scope);
			case EAnon(fieldNames, fieldValues):
				anonStructName(fieldNames, fieldValues, scope);
			case _:
				dynamicLocalAssignedType(value, scope);
		}
	}

	function closureVectorTypeForLambdaArgImpl(local:String, body:HxExpr, scope:CppRenderScope):String {
		final candidates = new StringMap<Bool>();
		candidates.set(local, true);
		final pushedValues = new StringMap<Array<HxExpr>>();
		final callArgTypes = new StringMap<Array<Array<String>>>();
		collectClosureVectorEvidenceFromExpr(body, scope, candidates, pushedValues, callArgTypes);
		if (!pushedValues.exists(local))
			return "";
		final elementType = closureVectorElementType(pushedValues.get(local), callArgTypes.exists(local) ? callArgTypes.get(local) : [], scope);
		return elementType.length == 0 ? "" : "std::vector<" + elementType + ">";
	}

	function closureVectorElementType(values:Array<HxExpr>, callShapes:Array<Array<String>>, scope:CppRenderScope):String {
		if (values == null)
			return "";
		for (value in values) {
			final typeName = switch (value) {
				case ELambda(args, body):
					inferredLambdaCppFunctionType(args, body, closureVectorCallArgTypes(callShapes, args.length), scope);
				case ECall(EIdent("__hxhx_optional_lambda"), [ELambda(args, body), EArrayDecl(_)]):
					inferredLambdaCppFunctionType(args, body, closureVectorCallArgTypes(callShapes, args.length), scope);
				case EAnon(fieldNames, fieldValues):
					anonStructName(fieldNames, fieldValues, scope);
				case _:
					dynamicLocalAssignedType(value, scope);
			}
			if (typeName.length > 0)
				return typeName;
		}
		return "";
	}

	function closureVectorCallArgTypes(callShapes:Array<Array<String>>, arity:Int):Array<String> {
		if (arity == 0)
			return [];
		if (callShapes == null)
			return [];
		for (shape in callShapes) {
			if (shape.length != arity)
				continue;
			var complete = true;
			for (typeName in shape)
				if (typeName == null || typeName.length == 0)
					complete = false;
			if (complete)
				return shape;
		}
		return [];
	}

	function firstNonEmptyType(values:Array<String>):String {
		if (values == null)
			return "";
		for (value in values)
			if (value != null && value.length > 0)
				return value;
		return "";
	}

	function isUnhintedEmptyArray(typeHint:String, init:Null<HxExpr>):Bool {
		if (StringTools.trim(typeHint == null ? "" : typeHint).length > 0)
			return false;
		return isEmptyArrayExpr(init);
	}

	function isEmptyArrayExpr(init:Null<HxExpr>):Bool {
		return switch (init) {
			case EArrayDecl(values):
				values.length == 0;
			case ENew(typePath, args): args.length == 0 && CppTypeModel.isStdArrayTypePath(typePath);
			case _:
				false;
		};
	}

	function boolMapHasEntries(values:StringMap<Bool>):Bool {
		for (_ in values.keys())
			return true;
		return false;
	}

	function inferStringMapLocalTypeOverridesFromStmtsImpl(scope:CppRenderScope, stmts:Array<HxStmt>):Void {
		final savedLocalTypes = copyStringMap(scope.localTypes);
		final savedLocalNames = copyStringMap(scope.localNames);
		final savedLocalNameCounts = copyIntMap(scope.localNameCounts);
		final candidates = new StringMap<String>();
		for (stmt in stmts)
			collectStringMapLocalTypeOverridesFromStmt(stmt, scope, candidates);
		scope.localTypes = savedLocalTypes;
		scope.localNames = savedLocalNames;
		scope.localNameCounts = savedLocalNameCounts;
	}

	function collectStringMapLocalTypeOverridesFromStmt(stmt:HxStmt, scope:CppRenderScope, candidates:StringMap<String>):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				withStringMapInferenceScope(scope, candidates, () -> {
					for (s in stmts)
						collectStringMapLocalTypeOverridesFromStmt(s, scope, candidates);
				});
			case SIf(cond, thenBranch, elseBranch, _):
				collectStringMapLocalTypeOverridesFromExpr(cond, scope, candidates);
				collectStringMapLocalTypeOverridesFromStmt(thenBranch, scope, candidates);
				if (elseBranch != null)
					collectStringMapLocalTypeOverridesFromStmt(elseBranch, scope, candidates);
			case SForIn(name, iterable, body, _):
				collectStringMapLocalTypeOverridesFromExpr(iterable, scope, candidates);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					collectStringMapLocalTypeOverridesFromStmt(body, scope, candidates);
				});
			case SForKeyValue(keyName, valueName, iterable, body, _):
				collectStringMapLocalTypeOverridesFromExpr(iterable, scope, candidates);
				final loopTypes = keyValueLoopTypes(iterable, scope);
				withScopedLocal(scope, sanitizeIdentifier(keyName), loopTypes[0], () -> {
					withScopedLocal(scope, sanitizeIdentifier(valueName), loopTypes[1], () -> {
						collectStringMapLocalTypeOverridesFromStmt(body, scope, candidates);
					});
				});
			case SWhile(cond, body, _) | SDoWhile(body, cond, _):
				collectStringMapLocalTypeOverridesFromExpr(cond, scope, candidates);
				collectStringMapLocalTypeOverridesFromStmt(body, scope, candidates);
			case SSwitch(scrutinee, _, bodies, _):
				collectStringMapLocalTypeOverridesFromExpr(scrutinee, scope, candidates);
				for (body in bodies)
					collectStringMapLocalTypeOverridesFromStmt(body, scope, candidates);
			case STry(tryBody, catches, _):
				collectStringMapLocalTypeOverridesFromStmt(tryBody, scope, candidates);
				for (c in catches)
					collectStringMapLocalTypeOverridesFromStmt(c.body, scope, candidates);
			case SVar(name, typeHint, init, _):
				if (init != null)
					collectStringMapLocalTypeOverridesFromExpr(init, scope, candidates);
				final local = declareLocalName(name, scope);
				final mapClass = mapClassNameFromNewExpr(init);
				final unhinted = StringTools.trim(typeHint == null ? "" : typeHint).length == 0;
				final arrowMapType = init == null ? "" : api.arrowMapLiteralCppType(init, scope);
				if (unhinted && arrowMapType.length > 0) {
					scope.localTypeOverrides.set(local, arrowMapType);
					scope.localTypes.set(local, arrowMapType);
				} else if (unhinted && mapClass.length > 0) {
					candidates.set(local, mapClass);
					scope.localTypes.set(local, defaultMapLocalType(mapClass));
				} else {
					final localType = cppLocalTypeHint(typeHint, init, scope);
					if (localType.length > 0)
						scope.localTypes.set(local, localType);
				}
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				collectStringMapLocalTypeOverridesFromExpr(expr, scope, candidates);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
		}
	}

	function collectStringMapLocalTypeOverridesFromExpr(expr:HxExpr, scope:CppRenderScope, candidates:StringMap<String>):Void {
		switch (expr) {
			case ECall(EField(EIdent(name), "set"), [key, value]) if (candidates.exists(localCppName(name, scope))):
				collectStringMapLocalTypeOverridesFromExpr(key, scope, candidates);
				collectStringMapLocalTypeOverridesFromExpr(value, scope, candidates);
				final local = localCppName(name, scope);
				final keyType = mapKeyTypeFromExpr(key, scope);
				final valueType = stringMapValueTypeFromExpr(value, scope);
				if (valueType.length > 0)
					setStringMapLocalTypeOverride(scope, local, candidates.get(local), keyType, valueType);
			case EBinop(_, left, right):
				collectStringMapLocalTypeOverridesFromExpr(left, scope, candidates);
				collectStringMapLocalTypeOverridesFromExpr(right, scope, candidates);
			case ECall(callee, args):
				collectStringMapLocalTypeOverridesFromExpr(callee, scope, candidates);
				for (arg in args)
					collectStringMapLocalTypeOverridesFromExpr(arg, scope, candidates);
			case EArrayAccess(array, index):
				collectStringMapLocalTypeOverridesFromExpr(array, scope, candidates);
				collectStringMapLocalTypeOverridesFromExpr(index, scope, candidates);
			case EField(receiver, _):
				collectStringMapLocalTypeOverridesFromExpr(receiver, scope, candidates);
			case EArrayDecl(elements):
				for (element in elements)
					collectStringMapLocalTypeOverridesFromExpr(element, scope, candidates);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				collectStringMapLocalTypeOverridesFromExpr(iterable, scope, candidates);
				withScopedLocal(scope, sanitizeIdentifier(name), iterableElementType(iterable, scope), () -> {
					if (guardExpr != null)
						collectStringMapLocalTypeOverridesFromExpr(guardExpr, scope, candidates);
					collectStringMapLocalTypeOverridesFromExpr(yieldExpr, scope, candidates);
				});
			case EUnop(_, _, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				collectStringMapLocalTypeOverridesFromExpr(inner, scope, candidates);
			case ETernary(cond, thenExpr, elseExpr):
				collectStringMapLocalTypeOverridesFromExpr(cond, scope, candidates);
				collectStringMapLocalTypeOverridesFromExpr(thenExpr, scope, candidates);
				collectStringMapLocalTypeOverridesFromExpr(elseExpr, scope, candidates);
			case EAnon(_, fieldValues):
				for (value in fieldValues)
					collectStringMapLocalTypeOverridesFromExpr(value, scope, candidates);
			case ESwitch(scrutinee, _, exprs):
				collectStringMapLocalTypeOverridesFromExpr(scrutinee, scope, candidates);
				for (caseExpr in exprs)
					collectStringMapLocalTypeOverridesFromExpr(caseExpr, scope, candidates);
			case _:
		}
	}

	function withStringMapInferenceScope(scope:CppRenderScope, candidates:StringMap<String>, fn:Void->Void):Void {
		final savedLocalTypes = copyStringMap(scope.localTypes);
		final savedLocalTypeOverrides = copyStringMap(scope.localTypeOverrides);
		final savedLocalNames = copyStringMap(scope.localNames);
		final savedLocalNameCounts = copyIntMap(scope.localNameCounts);
		final savedCandidates = copyStringMap(candidates);
		fn();
		scope.localTypes = savedLocalTypes;
		scope.localTypeOverrides = savedLocalTypeOverrides;
		scope.localNames = savedLocalNames;
		scope.localNameCounts = savedLocalNameCounts;
		restoreStringMap(candidates, savedCandidates);
	}

	function restoreStringMap(target:StringMap<String>, saved:StringMap<String>):Void {
		final stale = [for (key in target.keys()) if (!saved.exists(key)) key];
		for (key in stale)
			target.remove(key);
		for (key in saved.keys())
			target.set(key, saved.get(key));
	}

	function mapClassNameFromNewExpr(expr:Null<HxExpr>):String {
		return switch (expr) {
			case ENew(typePath, _):
				final className = sanitizeTypePath(typeBaseName(typePath));
				isInferredMapClassName(className) ? className : "";
			case _:
				"";
		}
	}

	function defaultMapLocalType(mapClass:String):String {
		final cleanClass = sanitizeTypePath(typeBaseName(mapClass));
		return switch (cleanClass) {
			case "Map":
				"std::shared_ptr<Map<std::string, std::string>>";
			case _:
				"std::shared_ptr<" + cleanClass + "<std::string>>";
		};
	}

	function mapKeyTypeFromExpr(expr:HxExpr, scope:CppRenderScope):String {
		final explicit = exprCppType(expr, scope);
		if (explicit.length > 0)
			return explicit;
		final inferred = inferExprCppType(expr, scope);
		if (inferred.length > 0)
			return inferred;
		return isStringLike(expr) ? "std::string" : "int";
	}

	function stringMapValueTypeFromExpr(expr:HxExpr, scope:CppRenderScope):String {
		final explicit = exprCppType(expr, scope);
		if (explicit.length > 0)
			return explicit;
		final inferred = inferExprCppType(expr, scope);
		return inferred.length > 0 ? inferred : "std::string";
	}

	function setStringMapLocalTypeOverride(scope:CppRenderScope, local:String, mapClass:String, keyType:String, valueType:String):Void {
		final cleanClass = sanitizeTypePath(typeBaseName(mapClass == null ? "" : mapClass));
		if (cleanClass.length == 0)
			return;
		final typeName = mapLocalType(cleanClass, keyType, valueType);
		final existing = scope.localTypeOverrides.get(local);
		if (existing != null && existing.length > 0 && existing != typeName) {
			final currentLocalType = scope.localTypes.get(local);
			final currentIsFreshDefault = currentLocalType == defaultMapLocalType(cleanClass);
			if ((mapClassNameFromCppMapType(existing) == cleanClass && !currentIsFreshDefault)
				|| mapClassNameFromCppMapType(currentLocalType) != cleanClass)
				return;
		}
		scope.localTypeOverrides.set(local, typeName);
		scope.localTypes.set(local, typeName);
	}

	function mapLocalType(mapClass:String, keyType:String, valueType:String):String {
		final cleanClass = sanitizeTypePath(typeBaseName(mapClass == null ? "" : mapClass));
		return switch (cleanClass) {
			case "Map":
				"std::shared_ptr<Map<"
				+ (keyType == null || keyType.length == 0 ? "std::string" : keyType)
				+ ", "
				+ valueType
				+ ">>";
			case _:
				"std::shared_ptr<" + cleanClass + "<" + valueType + ">>";
		};
	}

	function mapClassNameFromCppMapType(typeName:String):String {
		if (typeName == null)
			return "";
		final prefix = "std::shared_ptr<";
		if (!StringTools.startsWith(typeName, prefix) || !StringTools.endsWith(typeName, ">"))
			return "";
		final inner = typeName.substr(prefix.length, typeName.length - prefix.length - 1);
		final genericStart = inner.indexOf("<");
		final className = genericStart >= 0 ? inner.substr(0, genericStart) : inner;
		return isInferredMapClassName(className) ? sanitizeTypePath(typeBaseName(className)) : "";
	}

	inline function copyStringMap(map:StringMap<String>):StringMap<String> {
		return api.copyStringMap(map);
	}

	inline function copyIntMap(map:StringMap<Int>):StringMap<Int> {
		return api.copyIntMap(map);
	}

	inline function sanitizeIdentifier(name:String):String {
		return api.sanitizeIdentifier(name);
	}

	inline function sanitizeTypePath(path:String):String {
		return api.sanitizeTypePath(path);
	}

	inline function typeBaseName(name:String):String {
		return api.typeBaseName(name);
	}

	inline function isInferredMapClassName(className:String):Bool {
		return api.isInferredMapClassName(className);
	}

	inline function exprCppType(expr:HxExpr, scope:CppRenderScope):String {
		return api.exprCppType(expr, scope);
	}

	inline function inferExprCppType(expr:HxExpr, scope:CppRenderScope):String {
		return api.inferExprCppType(expr, scope);
	}

	inline function isStringLike(expr:HxExpr):Bool {
		return api.isStringLike(expr);
	}

	inline function dynamicLocalAssignedType(expr:HxExpr, scope:CppRenderScope):String {
		return api.dynamicLocalAssignedType(expr, scope);
	}

	inline function anonStructName(fieldNames:Array<String>, fieldValues:Array<HxExpr>, scope:CppRenderScope):String {
		return api.anonStructName(fieldNames, fieldValues, scope);
	}

	inline function inferredLambdaCppFunctionType(args:Array<String>, body:HxExpr, argTypes:Array<String>, scope:CppRenderScope):String {
		return api.inferredLambdaCppFunctionType(args, body, argTypes, scope);
	}

	inline function closureCallableArgType(expr:HxExpr, scope:CppRenderScope):String {
		return api.closureCallableArgType(expr, scope);
	}

	inline function localCppName(name:String, scope:CppRenderScope):String {
		return api.localCppName(name, scope);
	}

	inline function declareLocalName(name:String, scope:CppRenderScope):String {
		return api.declareLocalName(name, scope);
	}

	inline function cppLocalTypeHint(typeHint:String, init:Null<HxExpr>, scope:CppRenderScope):String {
		return api.cppLocalTypeHint(typeHint, init, scope);
	}

	inline function iterableElementType(iterable:HxExpr, scope:CppRenderScope):String {
		return api.iterableElementType(iterable, scope);
	}

	inline function keyValueLoopTypes(iterable:HxExpr, scope:CppRenderScope):Array<String> {
		return api.keyValueLoopTypes(iterable, scope);
	}

	inline function withScopedLocal(scope:CppRenderScope, name:String, typeName:String, fn:Void->Void):Void {
		api.withScopedLocal(scope, name, typeName, fn);
	}
}
