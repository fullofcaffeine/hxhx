package backend.ocaml;

import TypedExactCallSource.TypedExactInstanceCall;

/**
	Select the function that one typed instance call reaches when the method may be overridden.

	`Stage3OcamlVirtualDispatch` decides which methods have dispatchers. This
	function applies that decision to one call:

	- `super.name(...)` becomes a call on `this` to the direct function of the
	  ancestor that typing selected, so it never dispatches back to the override
	  that contains it.
	- `receiver.name(...)` keeps the method's own name, which is its dispatcher,
	  unless the receiver's static type proves that no override applies. Then it
	  names the direct function.

	Returns null when the call needs no change. Throws the planner's named error
	when the call needs dispatch that the method's shape does not support.
**/
function select(input:{
	call:TypedExactInstanceCall,
	occurrence:Null<TypedBackendInstanceCallOccurrence>,
	virtuals:Stage3OcamlVirtualDispatch,
	currentModule:String
}):Null<{receiver:HxExpr, method:String}> {
	final call = input.call;
	if (call.receiver.match(ESuper))
		return {receiver: EThis, method: input.virtuals.superCallTarget(call.owner, call.method)};
	final receiverType = input.occurrence == null ? null : input.occurrence.getReceiverType();
	final nominal = receiverType == null ? null : receiverType.unwrapNull().getNominalIdentity();
	final method = input.virtuals.requireCallTarget(call.owner, call.method, nominal == null ? null : nominal.getCanonicalName(), input.currentModule);
	return method == call.method ? null : {receiver: call.receiver, method: method};
}
