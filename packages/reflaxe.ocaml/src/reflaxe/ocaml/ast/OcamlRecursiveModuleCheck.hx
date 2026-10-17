package reflaxe.ocaml.ast;

/** Signature views retain checked type identities; printing needs its own runtime-use accounting. */
enum OcamlModuleSignatureItem {
	SValue(name:String, type:OcamlTypeExpr);
	SType(declarations:Array<OcamlTypeDecl>, isRec:Bool);
}

/** A rejected declaration cannot be hidden merely to make a recursive signature compile. */
enum OcamlRecursiveModuleProblem {
	OpaqueModule;
	MissingSignature(name:String);
	EagerInitializer(name:String);
	InvalidFunctionSignature(name:String);
	InvalidLiteralSignature(name:String);
	UnsupportedInternalBinding(name:String);
}

/** Success covers only the supplied declarations, not artifact ownership or group publication. */
enum OcamlRecursiveModuleResult {
	RecursiveModuleReady(signature:Array<OcamlModuleSignatureItem>, functionsOnly:Bool);
	RecursiveModuleRejected(problem:OcamlRecursiveModuleProblem);
}

/**
	Checks declarations before the caller validates recursive initialization order.

	Functions need explicit signatures. Literal Int, Bool and String values keep
	their existing bindings and types, but make the module unsafe as an OCaml
	recursion anchor. Every dependency cycle must still pass through a module
	containing only functions; the assembly owner checks that group-level rule.
	A call returning a function is still an eager initializer and fails.
	Compiler-internal bindings may contain only literal unit, so hiding an export
	cannot conceal a call, allocation, or other unrepresented initialization effect.
	Raw fragments fail even inside functions because module references are incomplete.
	The caller must also supply carrier preludes and resolve all artifact owners.
**/
function checkRecursiveModule(items:Array<OcamlModuleItem>):OcamlRecursiveModuleResult {
	if (OcamlModuleReferences.collect(items).hasOpaqueText)
		return RecursiveModuleRejected(OpaqueModule);
	final signature:Array<OcamlModuleSignatureItem> = [];
	var functionsOnly = true;
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
								return RecursiveModuleRejected(UnsupportedInternalBinding(binding.name));
						}
					}
					final literal = literalType(binding.expr);
					if (literal != null) {
						if (binding.signature != null)
							switch (binding.signature) {
								case TIdent(name) if (name == literal):
								case _: return RecursiveModuleRejected(InvalidLiteralSignature(binding.name));
							}
						signature.push(SValue(binding.name, TIdent(literal)));
						functionsOnly = false;
						continue;
					}
					final arity = switch (value) {
						case EFun(parameters, _) if (parameters.length > 0): parameters.length;
						case _:
							return RecursiveModuleRejected(EagerInitializer(binding.name));
					};
					if (binding.signature == null)
						return RecursiveModuleRejected(MissingSignature(binding.name));
					var remainder = binding.signature;
					for (_ in 0...arity)
						switch (remainder) {
							case TArrow(_, result): remainder = result;
							case _: return RecursiveModuleRejected(InvalidFunctionSignature(binding.name));
						}
					signature.push(SValue(binding.name, binding.signature));
				}
		}
	return RecursiveModuleReady(signature, functionsOnly);
}

/** Only literal storage is inferred; annotations must preserve that exact type. */
private function literalType(expression:OcamlExpr):Null<String> {
	return switch (expression) {
		case EConst(CInt(_)): "int";
		case EConst(CBool(_)): "bool";
		case EConst(CString(_)): "string";
		case EPos(_, inner): literalType(inner);
		case EAnnot(inner, TIdent(name)): literalType(inner) == name ? name : null;
		case _: null;
	};
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
