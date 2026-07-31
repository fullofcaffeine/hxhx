package backend.cpp;

/**
	Reusable argument and local setup computed before rendering one C++ function.

	The snapshot contains only copied maps. A render scope may replay it within
	the same program lookup without sharing mutable method-local state.
**/
typedef CppFunctionScopePrep = {
	var argTypeOverrides:haxe.ds.StringMap<String>;
	var localTypeOverrides:haxe.ds.StringMap<String>;
	var argLocalTypes:haxe.ds.StringMap<String>;
	var argLocalTypeHints:haxe.ds.StringMap<String>;
	var argLocalNames:haxe.ds.StringMap<String>;
	var argLocalNameCounts:haxe.ds.StringMap<Int>;
}
