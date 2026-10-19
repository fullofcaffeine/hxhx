package backend.ocaml;

/** The exact method body and emitted receiver ABI selected by the native emitter. */
typedef MethodValueInput = {
	final occurrence:TypedBackendMethodOccurrence;
	final reference:String;
	final signature:EmitterCallSig;
	final emit:HxExpr->String;
	final names:Stage3OcamlLocalNames;
}

/**
	Bind an ordinary method before later call arguments execute their statements.

	Native methods are functions whose first argument is the receiver, rather
	than fields in the receiver's anonymous record. Partial application captures
	that receiver immediately and retains the method's existing parameter ABI.
	A zero-argument method needs a unit wrapper so capture does not invoke it.
	Reject a null receiver before binding: nullable method-value transport is
	not supported yet, and binding a stateless method would falsely succeed.
	Shared typing instantiates each generic capture and checks its later uses.
	The emitted ordinary body can retain OCaml polymorphism; declaration type
	parameters alone do not require another callable adapter. Dynamic replacement
	and optional/rest adapters still need their own checked storage contracts.
 */
function render(input:MethodValueInput):String {
	final occurrence = input.occurrence;
	if (occurrence == null || occurrence.getUse() != ValueRead || input.names == null)
		throw "OCaml method value requires its exact capture and local naming owner";
	final declaration = occurrence.getDeclaration();
	declaration.requireSupportedImplementation();
	final signature = input.signature;
	if (declaration.getIsDynamic() || !declaration.getHasBody())
		throw "OCaml method value requires an ordinary implemented method";
	if (signature == null || !signature.needsReceiver || signature.expected < 1 || signature.hasRest || signature.paramFillable.contains(true))
		throw "OCaml method value requires its fixed required receiver ABI";
	final receiver = switch occurrence.getExpression() {
		case EField(receiver, _): receiver;
		case _: throw "OCaml method value lost its receiver selection";
	};
	return captureReceiver({
		receiver: receiver,
		emit: input.emit,
		names: input.names,
		bind: captured -> {
			final applied = input.reference + " (" + captured + ")";
			return signature.expected == 1 ? "fun () -> " + applied : applied;
		}
	});
}

/** Ordinary and runtime-backed methods share once-only capture and the explicit nullable-storage rejection. */
function captureReceiver(input:{
	receiver:HxExpr,
	emit:HxExpr->String,
	names:Stage3OcamlLocalNames,
	bind:String->String
}):String {
	final captured = input.names.internalName("__hx_method_receiver");
	return "(let "
		+ captured
		+ " = ("
		+ input.emit(input.receiver)
		+ ") in if HxRuntime.is_null (Obj.repr "
		+ captured
		+ ") then HxRuntime.hx_throw_typed (Obj.repr \"Capturing a method from a null receiver is not supported\") [\"String\"; \"Dynamic\"] else "
		+ input.bind(captured)
		+ ")";
}
