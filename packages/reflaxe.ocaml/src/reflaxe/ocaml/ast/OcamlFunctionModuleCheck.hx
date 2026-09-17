package reflaxe.ocaml.ast;

/** Signature views retain checked type identities; printing needs its own runtime-use accounting. */
enum OcamlModuleSignatureItem {
	SValue(name:String, type:OcamlTypeExpr);
	SType(declarations:Array<OcamlTypeDecl>, isRec:Bool);
}

/** A rejected declaration cannot be hidden merely to make a recursive signature compile. */
enum OcamlFunctionModuleProblem {
	OpaqueModule;
	MissingSignature(name:String);
	EagerInitializer(name:String);
	InvalidFunctionSignature(name:String);
	UnsupportedInternalBinding(name:String);
}

/** Success covers only the supplied declarations, not artifact ownership or group publication. */
enum OcamlFunctionModuleResult {
	FunctionModuleReady(signature:Array<OcamlModuleSignatureItem>);
	FunctionModuleRejected(problem:OcamlFunctionModuleProblem);
}

/**
	Checks the initial function-only recursive-module contract before printing.

	Every exported value must construct a function and have an explicit function
	signature. A call returning a function is still an eager initializer and fails.
	Compiler-internal bindings may contain only literal unit, so hiding an export
	cannot conceal a call, allocation, or other unrepresented initialization effect.
	Raw fragments fail even inside functions because module references are incomplete.
	The caller must also supply carrier preludes and resolve all artifact owners.
**/
function checkFunctionModule(items:Array<OcamlModuleItem>):OcamlFunctionModuleResult {
	if (OcamlModuleReferences.collect(items).hasOpaqueText)
		return FunctionModuleRejected(OpaqueModule);
	final signature:Array<OcamlModuleSignatureItem> = [];
	for (item in items)
		switch (item) {
			case IType(declarations, isRec):
				signature.push(SType(declarations.copy(), isRec));
			case ILet(bindings, _):
				for (binding in bindings) {
					final value = withoutAnnotations(binding.expr);
					if (binding.visibility == CompilerInternal) {
						switch (value) {
							case EConst(CUnit):
								continue;
							case _:
								return FunctionModuleRejected(UnsupportedInternalBinding(binding.name));
						}
					}
					final arity = switch (value) {
						case EFun(parameters, _) if (parameters.length > 0): parameters.length;
						case _:
							return FunctionModuleRejected(EagerInitializer(binding.name));
					};
					if (binding.signature == null)
						return FunctionModuleRejected(MissingSignature(binding.name));
					var remainder = binding.signature;
					for (_ in 0...arity)
						switch (remainder) {
							case TArrow(_, result): remainder = result;
							case _: return FunctionModuleRejected(InvalidFunctionSignature(binding.name));
						}
					signature.push(SValue(binding.name, binding.signature));
				}
		}
	return FunctionModuleReady(signature);
}

/** Debug and type wrappers do not change whether constructing a value runs code. */
private function withoutAnnotations(expression:OcamlExpr):OcamlExpr {
	var current = expression;
	while (true)
		switch (current) {
			case EPos(_, inner), EAnnot(inner, _):
				current = inner;
			case _:
				return current;
		}
}
