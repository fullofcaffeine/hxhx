package backend.cpp;

import backend.cpp.CppManagedStoragePlan.CppManagedFunctionPlan;

/** Checked storage and type application used inside a real method or nested callable body. */
typedef CppManagedBodyStorage = {
	> CppManagedCallableStorage,
	final abstractReceiverType:Null<TyType>;
	function assertCurrent():Void;
	function resolveType(type:TyType):TyType;
	function resolveSemanticType(type:TyType):TyType;
	function getDeclarations(owner:CppManagedFunctionOwner):Array<TypedCaptureBinding>;
	function assertUninitializedLocal(binding:TyLocalBinding):Void;
	function requireClosure(expression:HxExpr):CppManagedFunctionPlan;
	function requireAscribedClosure(expression:HxExpr):HxExpr;
}
