package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.OcamlDeclarationSignature;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicCarrierModel;

using Lambda;

/** Detached method identity shared by a declaration, its binder, and each use. */
typedef OcamlMethodDispatchSignature = {
	final key:String;
	final methodName:String;
	final parameterTypes:Array<String>;
	final parameterCarriers:Array<String>;
	final resultType:String;
	final resultCarrier:String;
}

/**
	Combines a closed Haxe method type with independently selected native types.

	The caller must obtain the native signature from the declaration representation
	owner. This function never invents a carrier. Argument names and typedef aliases
	do not change the contract; argument order, nullability, and native types do.
	Receiver allocation and final-body ownership remain separate program proofs.
**/
function selectMethodSignature(field:ClassField, nativeSignature:OcamlDeclarationSignature, nativeModule:String):Null<OcamlMethodDispatchSignature> {
	if (nativeModule.length == 0 || field.params.length != 0 || field.overloads.get().length != 0 || field.meta.has(":native"))
		return null;
	switch (field.kind) {
		case FMethod(MethNormal | MethInline):
		case _:
			return null;
	}
	final method = switch (TypeTools.follow(field.type)) {
		case TFun(arguments, result): {arguments: arguments, result: result};
		case _: return null;
	};
	if (method.arguments.length != nativeSignature.parameters.length)
		return null;
	final parameterTypes:Array<String> = [];
	final parameterCarriers:Array<String> = [];
	for (index in 0...method.arguments.length) {
		final argument = method.arguments[index];
		final source = closedTypeId(argument.t);
		final native = carrierId(nativeSignature.parameters[index], nativeModule);
		if (argument.opt || source == null || native == null)
			return null;
		parameterTypes.push(source);
		parameterCarriers.push(native);
	}
	final resultType = closedTypeId(method.result);
	final resultCarrier = carrierId(nativeSignature.result, nativeModule);
	if (resultType == null || resultCarrier == null)
		return null;
	final signature:OcamlMethodDispatchSignature = {
		key: "",
		methodName: field.name,
		parameterTypes: parameterTypes,
		parameterCarriers: parameterCarriers,
		resultType: resultType,
		resultCarrier: resultCarrier
	};
	return {
		key: signatureKey(signature),
		methodName: signature.methodName,
		parameterTypes: parameterTypes.copy(),
		parameterCarriers: parameterCarriers.copy(),
		resultType: resultType,
		resultCarrier: resultCarrier
	};
}

/** Checks detached facts again before a method key can authorize native lookup. */
function requireMethodSignature(signature:OcamlMethodDispatchSignature):Void {
	if (signature.methodName.length == 0
		|| signature.parameterTypes.length != signature.parameterCarriers.length
		|| signature.resultType.length == 0
		|| signature.resultCarrier.length == 0
		|| signature.parameterTypes.exists(value -> value.length == 0)
		|| signature.parameterCarriers.exists(value -> value.length == 0)
		|| signature.key != signatureKey(signature))
		throw "reflaxe.ocaml [ocaml-method-dispatch:changed-signature]: method contract facts changed";
}

/** A typed binder cannot silently replace the native types captured by its key. */
function requireMethodNativeSignature(signature:OcamlMethodDispatchSignature, nativeSignature:OcamlDeclarationSignature, nativeModule:String):Void {
	requireMethodSignature(signature);
	if (nativeSignature.parameters.length != signature.parameterCarriers.length
		|| carrierId(nativeSignature.result, nativeModule) != signature.resultCarrier)
		throw "reflaxe.ocaml [ocaml-method-dispatch:changed-native-signature]: method result or arity changed";
	for (index in 0...nativeSignature.parameters.length)
		if (carrierId(nativeSignature.parameters[index], nativeModule) != signature.parameterCarriers[index])
			throw "reflaxe.ocaml [ocaml-method-dispatch:changed-native-signature]: method argument carrier changed";
}

/**
	Checks source eligibility without authorizing a native method binding.

	Structural dispatch uses this before selecting a view. Specialized iterator
	storage and methods with unresolved types remain with their existing owners.
	A selected method still needs an independently proved native signature.
**/
function hasClosedDispatchSourceType(type:Type):Bool {
	return closedTypeId(type) != null;
}

private function signatureKey(signature:OcamlMethodDispatchSignature):String {
	return "method-dispatch:" + Sha256.encode(frame([
		"ocaml-method-dispatch-signature-v1",
		signature.methodName,
		frame(signature.parameterTypes),
		frame(signature.parameterCarriers),
		signature.resultType,
		signature.resultCarrier
	]));
}

private function frame(values:Array<String>):String {
	return values.map(value -> value.length + ":" + value).join("");
}

/** Names source types without argument-name noise or request-local compiler IDs. */
private function closedTypeId(type:Type, depth:Int = 0):Null<String> {
	if (depth > 64)
		return null;
	function child(value:Type):Null<String>
		return closedTypeId(value, depth + 1);
	return switch (type) {
		case TLazy(resolve): child(resolve());
		case TMono(reference):
			final resolved = reference.get();
			resolved == null ? null : child(resolved);
		case TType(reference, parameters):
			final declaration = reference.get();
			child(TypeTools.applyTypeParameters(declaration.type, declaration.params, parameters));
		case TAbstract(reference, parameters):
			final declaration = reference.get();
			if (declaration.pack.length != 0) null else switch ([declaration.name, parameters]) {
				case ["Int" | "Bool" | "Void", []]: declaration.name;
				case ["Null", [inner]]:
					final selected = child(inner);
					selected == null ? null : "null:" + frame([selected]);
				case _: null;
			}
		case TInst(reference, parameters):
			final declaration = reference.get();
			if (declaration.module == "String" && declaration.pack.length == 0 && declaration.name == "String" && parameters.length == 0) {
				"String";
			} else if (declaration.module == "Array" && declaration.pack.length == 0 && declaration.name == "Array" && parameters.length == 1) {
				final element = child(parameters[0]);
				element == null ? null : "array:" + frame([element]);
			} else if (parameters.length != 0 || declaration.params.length != 0 || declaration.isExtern || declaration.meta.has(":native")) {
				null;
			} else switch (declaration.kind) {
				case KNormal: "class:" + frame([declaration.module, declaration.pack.concat([declaration.name]).join(".")]);
				case _: null;
			}
		case TEnum(reference, []) if (!reference.get().isExtern && reference.get().params.length == 0):
			final declaration = reference.get();
			"enum:" + frame([declaration.module, declaration.pack.concat([declaration.name]).join(".")]);
		case TFun(arguments, result):
			final parts:Array<String> = [];
			for (argument in arguments) {
				final selected = child(argument.t);
				if (argument.opt || selected == null)
					return null;
				parts.push(selected);
			}
			final selectedResult = child(result);
			selectedResult == null ? null : "function:" + frame([frame(parts), selectedResult]);
		case TAnonymous(reference) if (OcamlDynamicCarrierModel.anonymousUsesHxAnon(type)):
			final fields = reference.get().fields.copy();
			switch (reference.get().status) {
				case AClosed:
				case _: return null;
			}
			fields.sort((left, right) -> left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
			final parts:Array<String> = [];
			for (field in fields) {
				final selected = child(field.type);
				if (selected == null || field.params.length != 0 || field.overloads.get().length != 0)
					return null;
				parts.push(frame([
					field.name,
					Std.string(field.kind),
					field.meta.has(":optional") ? "optional" : "required",
					selected
				]));
			}
			"anonymous:" + frame(parts);
		case _: null;
	};
}

/** Qualifies local nominal types while excluding use-occurrence IDs from ABI identity. */
private function carrierId(type:OcamlTypeExpr, nativeModule:String):Null<String> {
	function name(value:String):String {
		return value.indexOf(".") >= 0
			|| ["int", "bool", "string", "unit", "float", "list", "option", "ref", "array"].contains(value) ? value : nativeModule + "." + value;
	}
	function children(values:Array<OcamlTypeExpr>):Null<String> {
		final parts:Array<String> = [];
		for (value in values) {
			final selected = carrierId(value, nativeModule);
			if (selected == null)
				return null;
			parts.push(selected);
		}
		return frame(parts);
	}
	return switch (type) {
		case TIdent(value): "named:" + name(value);
		case TRuntimeIdent(reference): "runtime:" + reference.exactSymbol;
		case TRuntimeApp(reference, parameters):
			final selected = children(parameters);
			selected == null ? null : "runtime-app:" + frame([reference.exactSymbol, selected]);
		case TApp(value, parameters):
			final selected = children(parameters);
			selected == null ? null : "app:" + frame([name(value), selected]);
		case TArrow(from, to):
			final selected = children([from, to]);
			selected == null ? null : "arrow:" + selected;
		case TTuple(items):
			final selected = children(items);
			selected == null ? null : "tuple:" + selected;
		case TVar(_) | TRecord(_): null;
	};
}
#end
