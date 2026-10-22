package backend.cpp;

import backend.cpp.CppControlRegion.CppControlFunctionResult;
import backend.cpp.CppControlRegion.CppControlRegionServices;

/**
	Render an exact ordinary method or lowered closure with its selected return transport.
	Control regions remain owned by CppControlRegion. Managed returns publish into
	a caller-owned root before local roots unwind; leaf results return directly.
	Expression and statement services must supply the matching managed storage
	operations and preserve temporary roots across collecting subexpressions.
	This boundary does not bridge old native carriers or invent a missing body.
 */
class CppManagedFunctionBody {
	final plan:CppManagedCallableStorage;
	final owner:CppManagedFunctionOwner;

	public function new(plan:CppManagedCallableStorage, owner:CppManagedFunctionOwner) {
		if (plan == null)
			throw "managed function body requires an exact storage plan";
		this.plan = plan;
		this.owner = owner;
		plan.requireFunction(owner);
	}

	public function render(destination:Null<String>, scope:Null<CppRenderScope>, services:CppControlRegionServices):String {
		final closure = plan.requireFunction(owner);
		final result:CppControlFunctionResult = switch closure.abi.result {
			case NoResult:
				if (destination != null)
					throw "Void managed function cannot have a result root";
				NoValue;
			case DirectResult:
				if (destination != null)
					throw "leaf managed function cannot have a result root";
				DirectValue(closure.abi.nativeReturnType());
			case RootedResult: RootedValue(destination);
		};
		return switch owner {
			case Root(projection): CppControlRegion.renderRoot(projection, result, scope, services);
			case Closure(expression):
				final body = switch expression {
					case ELambda(_, body): body;
					case _: throw "managed function body requires a projected closure";
				};
				CppControlRegion.renderFunction(body, result, scope, services);
		};
	}
}
