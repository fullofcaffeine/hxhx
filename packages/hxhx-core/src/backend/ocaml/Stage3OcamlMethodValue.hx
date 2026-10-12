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
	Dynamic replacement and generic/optional/rest adapters need their own checked
	storage contracts; they must not fall back to reading a nonexistent field.
 */
function render(input:MethodValueInput):String {
	final occurrence = input.occurrence;
	if (occurrence == null || occurrence.getUse() != ValueRead || input.names == null)
		throw "OCaml method value requires its exact capture and local naming owner";
	final declaration = occurrence.getDeclaration();
	declaration.requireSupportedImplementation();
	final signature = input.signature;
	if (declaration.getIsDynamic() || declaration.getTypeParameters().length != 0 || !declaration.getHasBody())
		throw "OCaml method value requires an ordinary implemented method";
	if (signature == null || !signature.needsReceiver || signature.expected < 1 || signature.hasRest || signature.paramFillable.contains(true))
		throw "OCaml method value requires its fixed required receiver ABI";
	final receiver = switch occurrence.getExpression() {
		case EField(receiver, _): receiver;
		case _: throw "OCaml method value lost its receiver selection";
	};
	final captured = input.names.internalName("__hx_method_receiver");
	final applied = input.reference + " (" + captured + ")";
	return "(let "
		+ captured
		+ " = ("
		+ input.emit(receiver)
		+ ") in "
		+ (signature.expected == 1 ? "fun () -> " + applied : applied)
		+ ")";
}
