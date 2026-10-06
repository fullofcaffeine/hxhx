package backend.cpp;

import backend.cpp.CppControlRegion.CppControlRegionServices;
import backend.cpp.CppManagedRootedExpression.CppManagedRootedExpressionInput;

/** Connect exact managed storage to shared control rendering without legacy carrier fallback. */
function create(input:CppManagedRootedExpressionInput):CppControlRegionServices {
	return fromExpression(new CppManagedRootedExpression(input));
}

/** Entry defaults and body effects share one allocator for expression temporary names. */
function fromExpression(rooted:CppManagedRootedExpression):CppControlRegionServices {
	return {
		statement: rooted.renderStatement,
		returnValue: rooted.renderControlValue,
		directReturn: rooted.renderDirectReturn,
		rootedValue: rooted.renderRootedReturn,
		forLoop: rooted.renderFor,
		switchArms: rooted.renderSwitch
	};
}
