package backend.cpp;

/**
	Reusable argument and local setup computed before rendering one C++ function.

	The snapshot contains copied representation facts keyed by transport name.
	Target symbols belong to the executable plan and are never restored from a
	type-analysis cache.
**/
typedef CppFunctionScopePrep = {
	var argTypeOverrides:haxe.ds.StringMap<String>;
	var localTypeOverrides:haxe.ds.StringMap<String>;
	var argLocalTypes:haxe.ds.StringMap<String>;
	var argLocalTypeHints:haxe.ds.StringMap<String>;
}
