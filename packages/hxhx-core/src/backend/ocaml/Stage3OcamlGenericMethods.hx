package backend.ocaml;

import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlGenericCallEmitter.convertArrow;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.matchInstantiation;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.runtimeHelpers;

private typedef GenericMethod = {
	final functionBody:TypedFunction;
	final declaration:TyDeclarationInfo;
	final declarationSignature:String;
	final bodyRevision:String;
	final owned:Array<String>;
	final signature:Null<OcamlGenericValueShape>;
};

/**
	Keep native generic method bodies, direct calls, and captures on one erased ABI.
	The shared target owns boxing and unboxing. This adapter supplies native typed
	identities and binds each emitted operand before shared syntax consumes it.
	Unproved parameter or container layouts cannot borrow a scalar conversion.
 */
class Stage3OcamlGenericMethods {
	final methods:Map<String, GenericMethod> = [];
	final printer = new OcamlASTPrinter();
	var nextName = 0;
	var methodCount = 0;

	public function new(modules:Array<TypedModule>) {
		for (module in modules)
			for (owner in module.getTypedClasses())
				for (fn in owner.getFunctions()) {
					final declaration = fn.getDeclaration();
					if (declaration == null
						|| declaration.getTypeParameters().length == 0
						|| !declaration.getHasBody()
						|| declaration.getIsExtern())
						continue;
					final signature = declaration.getSignature();
					final owned = declaration.getTypeParameterIds().map(parameter -> parameter.getCanonicalKey());
					if (!needsErasedBoundary(signature.getReturnType(), owned)
						&& !Lambda.exists(signature.getArgs(), type -> needsErasedBoundary(type, owned)))
						continue;
					final classInfo = Std.downcast(owner.getSemanticInfo(), TyClassInfo);
					final supported = classInfo != null
						&& !classInfo.getIsExtern()
						&& !classInfo.getIsInterface()
						&& classInfo.getTypeParameters().length == 0
						&& !declaration.getIsDynamic()
						&& !signature.getArgOptional().contains(true)
						&& !signature.getArgRest().contains(true);
					final key = declaration.getIdentity().getCanonicalKey();
					if (methods.exists(key))
						throw "native generic plan received a duplicate declaration";
					methodCount++;
					methods.set(key, {
						functionBody: fn,
						declaration: declaration,
						declarationSignature: TyCallableSignature.fromDeclaration(declaration).getFunctionType().getSemanticKey(),
						bodyRevision: CompilerTypedTreeRevision.functionBody(fn),
						owned: owned,
						signature: supported ? shape(TyType.functionType(signature.getArgs(), signature.getReturnType())) : null
					});
				}
	}

	/**
		Only values crossing a method interface need this method's erased storage.
		A generic argument inside an array or class does not change that container's
		representation. Its existing storage owner remains responsible for elements.
		Callback arguments and results do cross the interface and need adapters.
	 */
	static function needsErasedBoundary(input:TyType, owned:Array<String>):Bool {
		final type = TyAliasExpansion.reveal(input);
		if (type.isTypeParameter())
			return owned.contains(type.getTypeParameterIdentity().getCanonicalKey());
		if (type.isNullable())
			return needsErasedBoundary(type.unwrapNull(), owned);
		return type.isFunction()
			&& (needsErasedBoundary(type.getFunctionReturn(), owned)
				|| Lambda.exists(type.getFunctionParameters(), parameter -> needsErasedBoundary(parameter.type, owned)));
	}

	/** A native method owns its type-parameter storage; another method's T is not interchangeable. */
	public function isErased(projection:TypedBackendFunctionProjection, input:TyType):Bool {
		final type = input == null ? null : TyAliasExpansion.reveal(input);
		if (projection == null || type == null || !type.isTypeParameter())
			return false;
		final declaration = projection.requireSemanticDeclaration();
		final method = declaration == null ? null : methods.get(declaration.getIdentity().getCanonicalKey());
		if (method == null || method.signature == null)
			return false;
		requireOwner(method, declaration);
		if (projection.getBodyRevision() != method.bodyRevision)
			throw "native generic body belongs to a changed typed owner";
		return method.owned.contains(type.getTypeParameterIdentity().getCanonicalKey());
	}

	/** Only shared, proven shapes enter a generic declaration or one of its instantiations. */
	static function shape(input:TyType):Null<OcamlGenericValueShape> {
		final type = TyAliasExpansion.reveal(input);
		if (type.isTypeParameter())
			return Erased(type.getTypeParameterIdentity().getCanonicalKey());
		if (type.isFunction()) {
			final parameters:Array<OcamlGenericValueShape> = [];
			for (parameter in type.getFunctionParameters()) {
				final value = shape(parameter.type);
				if (value == null || parameter.isOptional || parameter.isRest || value == EffectOnly)
					return null;
				parameters.push(value);
			}
			final result = shape(type.getFunctionReturn());
			return result == null ? null : FunctionValue(parameters, result);
		}
		return type.getSemanticKey() == "primitive:Float" ? Floating : Stage3OcamlCallableSelection.valueShape(type);
	}

	static function requireOwner(method:GenericMethod, declaration:TyDeclarationInfo):Void {
		if (method.declaration != declaration
			|| method.declarationSignature != TyCallableSignature.fromDeclaration(declaration).getFunctionType().getSemanticKey())
			throw "native generic use belongs to another declaration";
		method.functionBody.assertParsedBodyCurrent();
		declaration.requireSupportedImplementation();
		if (method.signature == null)
			throw "native generic method requires a supported ordinary signature: " + declaration.getIdentity().getCanonicalKey();
	}

	function convert(source:OcamlGenericValueShape, destination:OcamlGenericValueShape, value:String, names:Stage3OcamlLocalNames):String {
		final conversion = crossing(source, destination);
		if (conversion == null)
			throw "native generic use lacks a shared storage conversion";
		final helpers = runtimeHelpers(conversion, "native-generic");
		final operand = names.internalName("__hx_generic_value");
		final converted = convertArrow(conversion, EIdent(operand), "native-generic", role -> names.internalName("__hx_" + role + "_" + nextName++),
			(role, symbol) -> {
				if (!Lambda.exists(helpers, helper -> helper.role == role && helper.symbol == symbol))
					throw "native generic syntax requested an unplanned helper";
				return EIdent(symbol);
			});
		return "(let " + operand + " = (" + value + ") in " + printer.printExpr(converted) + ")";
	}

	/** Lookup validates exact source occurrence and body membership before this adapter selects a method. */
	public function render(input:{
		expression:HxExpr,
		lookup:HxExpr->Null<TypedExpr>,
		emit:HxExpr->String,
		reference:TyDeclarationInfo->String,
		names:Stage3OcamlLocalNames
	}):Null<String> {
		if (methodCount == 0 || input.lookup == null || input.names == null)
			return null;
		// These are negative filters only. A candidate still needs the original
		// typed occurrence; a reserved marker never supplies emission authority.
		switch input.expression {
			case ECall(_, _):
				final selectedStatic = TypedExactStaticCallSource.decode(input.expression);
				final selectedInstance = TypedExactCallSource.decodeInstance(input.expression);
				final key = selectedStatic != null ? selectedStatic.declaration : selectedInstance == null ? null : selectedInstance.declaration;
				if (key == null || !methods.exists(key))
					return null;
			case EIdent(name):
				if (input.names.findType(name) != null)
					return null;
			case EField(_, _):
			case _:
				return null;
		}
		final source = input.lookup(input.expression);
		final declaration = source == null ? null : source.getDeclaration();
		final method = declaration == null ? null : methods.get(declaration.getIdentity().getCanonicalKey());
		if (method == null)
			return null;
		requireOwner(method, declaration);
		if (source.getTag() == Call) {
			source.assertArgumentBinding();
			final staticCall = TypedExactStaticCallSource.decode(input.expression);
			final instanceCall = TypedExactCallSource.decodeInstance(input.expression);
			final arguments = staticCall != null ? staticCall.arguments : instanceCall == null ? null : instanceCall.arguments;
			if (arguments == null || source.getNamedArguments() == null)
				throw "native generic call lost its selected argument binding";
			final applied = source.getNamedArguments().getArguments().getFunctionType();
			final instantiation = shape(applied);
			if (instantiation == null || !matchInstantiation(method.signature, instantiation, method.owned, new Map()))
				throw "native generic call has an inconsistent instantiation";
			final signature = switch method.signature {
				case FunctionValue(parameters, result): {parameters: parameters, result: result};
				case _: throw "native generic declaration is not callable";
			};
			if (arguments.length != signature.parameters.length || source.getExpressions().length != arguments.length + 1)
				throw "native generic call changed its argument count";
			final values:Array<String> = [];
			if (!declaration.getIsStatic()) {
				if (instanceCall == null)
					throw "native generic instance call lost its receiver";
				values.push(input.emit(instanceCall.receiver));
			}
			for (index in 0...arguments.length) {
				final actual = shape(source.getExpressions()[index + 1].getType());
				if (actual == null)
					throw "native generic argument has no shared storage shape";
				values.push(convert(actual, signature.parameters[index], input.emit(arguments[index]), input.names));
			}
			final result = shape(source.getType());
			if (result == null)
				throw "native generic result has no shared storage shape";
			final called = values.length == 0 ? input.reference(declaration) + " ()" : Stage3OcamlCallOrder.render({
				callee: input.reference(declaration),
				arguments: values,
				names: input.names
			});
			return convert(signature.result, result, called, input.names);
		}
		if (source.getTag() != FieldRead && source.getTag() != NameRead)
			return null;
		final instantiated = shape(source.getType());
		if (instantiated == null || !matchInstantiation(method.signature, instantiated, method.owned, new Map()))
			throw "native generic capture has an inconsistent instantiation";
		if (declaration.getIsStatic()) {
			if (source.getTag() == FieldRead
				&& source.getExpressions().length > 0
				&& (source.getExpressions()[0].getTag() != NameRead || source.getExpressions()[0].getFieldInfo() != null))
				throw "native generic static capture requires a type receiver";
			return convert(method.signature, instantiated, input.reference(declaration), input.names);
		}
		final receiver = switch input.expression {
			case EField(receiver, _): receiver;
			case _: throw "native generic method capture lost its receiver";
		};
		return Stage3OcamlMethodValue.captureReceiver({
			receiver: receiver,
			emit: input.emit,
			names: input.names,
			bind: value -> {
				final applied = input.reference(declaration) + " (" + value + ")";
				return convert(method.signature, instantiated, declaration.getSignature().getArgs().length == 0 ? "(fun () -> " + applied + ")" : applied,
					input.names);
			}
		});
	}
}
