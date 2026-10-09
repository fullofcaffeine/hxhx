package backend.cpp;

import haxe.ds.StringMap;

/** Presence is distinct from a stored nullable representation fact. */
private typedef LocalEntry<T> = {
	final present:Bool;
	final value:Null<T>;
}

/**
	Run a nested rendering probe with all local representation maps restored.

	Executable identities, planned symbols, and explicit target temporaries belong
	to the whole function and are not lexical facts. Type parameters and return
	context belong to the function scope. This boundary restores local facts after
	normal completion and rejection, so an unsuccessful child cannot affect a retry.
**/
function isolate<T>(scope:CppRenderScope, body:Void->T):T {
	if (scope == null)
		return body();
	final types = scope.localTypes.copy();
	final hints = scope.localTypeHints.copy();
	final names = scope.localNames.copy();
	final counts = scope.localNameCounts.copy();
	final argumentOverrides = scope.argTypeOverrides.copy();
	final localOverrides = scope.localTypeOverrides.copy();
	function restore():Void {
		scope.localTypes = types;
		scope.localTypeHints = hints;
		scope.localNames = names;
		scope.localNameCounts = counts;
		scope.argTypeOverrides = argumentOverrides;
		scope.localTypeOverrides = localOverrides;
	}
	try {
		final result = body();
		restore();
		return result;
	} catch (error:haxe.Exception) {
		restore();
		throw error;
	}
}

/**
	Commit only a successful inference pass's argument and local type overrides.
	Traversal facts remain private to the pass; a rejection commits no results.
**/
function inferOverrides(scope:CppRenderScope, body:Void->Void):Void {
	final result = isolate(scope, () -> {
		body();
		return {arguments: scope.argTypeOverrides.copy(), locals: scope.localTypeOverrides.copy()};
	});
	scope.argTypeOverrides = result.arguments;
	scope.localTypeOverrides = result.locals;
}

/**
	Install one loop, catch, or lambda binding while retaining inference outputs
	for other locals. Only this binding's facts are restored after the child ends.
	This is narrower than isolate because inference must retain discoveries about
	captured values. The work is constant per map, independent of function size.
**/
function withBinding<T>(scope:CppRenderScope, name:String, typeName:String, body:Void->T):T {
	if (scope == null)
		return body();
	final types = capture(scope.localTypes, name);
	final hints = capture(scope.localTypeHints, name);
	final names = capture(scope.localNames, name);
	final counts = capture(scope.localNameCounts, name);
	final argumentOverrides = capture(scope.argTypeOverrides, name);
	final localOverrides = capture(scope.localTypeOverrides, name);
	if (typeName != null && typeName.length > 0)
		scope.localTypes.set(name, typeName);
	final symbol = scope.executableLocals != null
		&& scope.executableLocals.findLocal(name) != null ? scope.executableLocals.symbol(name) : name;
	scope.localNames.set(name, symbol);
	function restore():Void {
		restoreEntry(scope.localTypes, name, types);
		restoreEntry(scope.localTypeHints, name, hints);
		restoreEntry(scope.localNames, name, names);
		restoreEntry(scope.localNameCounts, name, counts);
		restoreEntry(scope.argTypeOverrides, name, argumentOverrides);
		restoreEntry(scope.localTypeOverrides, name, localOverrides);
	}
	try {
		final result = body();
		restore();
		return result;
	} catch (error:haxe.Exception) {
		restore();
		throw error;
	}
}

private function capture<T>(map:StringMap<T>, name:String):LocalEntry<T>
	return {present: map.exists(name), value: map.get(name)};

private function restoreEntry<T>(map:StringMap<T>, name:String, saved:LocalEntry<T>):Void {
	if (saved.present)
		map.set(name, saved.value);
	else
		map.remove(name);
}
