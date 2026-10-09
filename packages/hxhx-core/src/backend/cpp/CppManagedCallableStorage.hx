package backend.cpp;

import backend.cpp.CppManagedStoragePlan.CppManagedCellPlan;
import backend.cpp.CppManagedStoragePlan.CppManagedFunctionPlan;

/**
	Storage required to enter and return from a real callable body. A method plan
	can select its root or a nested closure; an initializer capture plan can select
	only its cataloged closures. The initializer expression itself has no callable
	signature, parameters, or return transport.
 */
typedef CppManagedCallableStorage = {
	function requireFunction(owner:CppManagedFunctionOwner):CppManagedFunctionPlan;
	function getCells():Array<CppManagedCellPlan>;
	function requireCell(binding:TyLocalBinding):CppManagedCellPlan;
}
