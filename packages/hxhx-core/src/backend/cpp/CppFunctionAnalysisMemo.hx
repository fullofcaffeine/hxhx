package backend.cpp;

/**
	Request-owned state for recursive C++ function analysis.

	One `CppClassLookup` creates this memo for one program render and shares it
	with every derived scope. Completed function-preparation and erased-return
	results may be reused within that render. The companion stacks prevent
	recursive analysis from re-entering the same function and must be empty after
	the corresponding analysis finishes or throws.
**/
class CppFunctionAnalysisMemo {
	/** Function signatures currently being prepared recursively. **/
	public final functionPreparationsInProgress:haxe.ds.StringMap<Bool>;

	/** Completed function-scope preparation snapshots by scoped signature. **/
	public final functionPreparations:haxe.ds.StringMap<CppFunctionScopePrep>;

	/** Function signatures currently being scanned for erased Dynamic returns. **/
	public final erasedDynamicReturnScansInProgress:haxe.ds.StringMap<Bool>;

	/** Completed erased Dynamic return decisions by scoped signature. **/
	public final erasedDynamicReturnResults:haxe.ds.StringMap<Bool>;

	/** Function signatures currently inferring argument or return C++ types. **/
	public final inferredSignaturesInProgress:haxe.ds.StringMap<Bool>;

	/** Completed inferred C++ argument types by declaration shape. **/
	public final functionArgumentTypes:haxe.ds.StringMap<Array<String>>;

	/** Completed inferred C++ return types by declaration shape. **/
	public final functionReturnTypes:haxe.ds.StringMap<String>;

	public function new() {
		functionPreparationsInProgress = new haxe.ds.StringMap<Bool>();
		functionPreparations = new haxe.ds.StringMap<CppFunctionScopePrep>();
		erasedDynamicReturnScansInProgress = new haxe.ds.StringMap<Bool>();
		erasedDynamicReturnResults = new haxe.ds.StringMap<Bool>();
		inferredSignaturesInProgress = new haxe.ds.StringMap<Bool>();
		functionArgumentTypes = new haxe.ds.StringMap<Array<String>>();
		functionReturnTypes = new haxe.ds.StringMap<String>();
	}
}
