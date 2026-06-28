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
	var localCppName:(String, CppRenderScope) -> String;
	var declareLocalName:(String, CppRenderScope) -> String;
	var cppLocalTypeHint:(String, Null<HxExpr>, CppRenderScope) -> String;
	var iterableElementType:(HxExpr, CppRenderScope) -> String;
	var keyValueLoopTypes:(HxExpr, CppRenderScope) -> Array<String>;
	var withScopedLocal:(CppRenderScope, String, String, Void->Void) -> Void;
}

/**
	C++ local type inference passes that run before source rendering.

	`CppTargetCore` owns emission. This module owns focused pre-render inference
	traversals that refine local type overrides without writing C++ source. Keep
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
				if (StringTools.trim(typeHint == null ? "" : typeHint).length == 0 && mapClass.length > 0) {
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
			case EUnop(_, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
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
