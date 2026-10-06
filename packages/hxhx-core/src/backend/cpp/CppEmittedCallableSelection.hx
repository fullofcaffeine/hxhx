package backend.cpp;

import backend.cpp.CppEmittedCallableContract.CppCallableGeneric;
import backend.cpp.CppEmittedCallableContract.CppCallableGenericOwner;
import backend.cpp.CppEmittedCallableContract.CppCallableParameter;
import backend.cpp.CppEmittedCallableContract.CppCallableParameterKind;
import backend.cpp.CppEmittedCallableContract.CppCallablePassingMode;
import backend.cpp.CppEmittedCallableContract.CppCallableStrategy;
import backend.cpp.CppEmittedCallableContract.CppCallableDefault;
import backend.cpp.CppEmittedCallableContract.CppCallableTrailingParameter;
import backend.cpp.CppTargetCore as Core;

/**
	Select a declaration's emitted callable shape once per request.
	The existing C++ preparation owns ordinary representation inference. This
	module owns the selected signature and keeps renderer-specific templates out
	of caller scopes. Recursive readers see a header, never a completed-cache entry
	that pretends body-dependent analysis finished.
 */
function select(fn:HxFunctionDecl, owner:HxClassDecl, lookup:CppClassLookup):CppEmittedCallableContract {
	final projection = lookup.typedProgram == null ? null : lookup.typedProgram.requireFunction(owner, fn);
	final memo = Core.functionAnalysisMemoForLookup(lookup);
	final cached = memo.emittedCallableContracts.get(fn);
	if (cached != null) {
		cached.assertOwner(owner, fn, projection);
		return cached;
	}
	final selecting = memo.emittedCallableSelectionsInProgress.get(fn);
	if (selecting != null) {
		selecting.assertOwner(owner, fn, projection);
		return selecting;
	}
	final scope = Core.renderScope(owner, lookup, "auto");
	Core.applyFunctionTypeParams(scope, fn);
	final strategy = selectStrategy(fn, owner, lookup);
	final neutral = switch (strategy) {
		case UtestNeutral(_): true;
		case _: false;
	};
	if (!neutral)
		Core.applyKnownStdlibFunctionArgOverrides(scope, fn);
	final hint = HxFunctionDecl.getReturnTypeHint(fn);
	final rawReturn = StringTools.trim(hint == null ? "" : hint);
	final headerReturn = switch (strategy) {
		case PolymorphicIsOfType | LambdaHas | AssertSameAs(_) | AssertSame(_): "bool";
		case AssertStringify | SerializerRun: "std::string";
		case UtestEq | UtestFunction | UtestValue | UtestAllow: "void";
		case UtestHook(event): event ? "std::function<void(std::any)>" : "std::function<void()>";
		case UtestNeutral(fast): fast ? Core.fastUtestAssertType(HxFunctionDecl.getReturnTypeHint(fn), HxDefaultValue.NoDefault,
				false) : Core.supportMethodSignatureReturnType(fn, owner, lookup);
		case RttiMeta | TypeErasedValue: Core.cppFunctionReturnType(fn, owner, lookup);
		case Ordinary: rawReturn.length == 0 ? "auto" : Core.cppReturnTypeHint(rawReturn, scope, lookup);
	};
	final header = build(fn, owner, projection, strategy, headerReturn, scope);
	final externalAnalysis = memo.inferredSignaturesInProgress.exists(Core.functionSignatureKey(owner, fn, lookup));
	memo.emittedCallableSelectionsInProgress.set(fn, header);
	var result = header;
	try {
		if (strategy == Ordinary) {
			final returnType = Core.cppMethodSignatureReturnType(fn, owner, lookup);
			final prepared = Core.renderScope(owner, lookup, returnType);
			Core.prepareFunctionTypeScope(prepared, fn);
			result = build(fn, owner, projection, strategy, returnType, prepared);
		}
	} catch (error:haxe.Exception) {
		memo.emittedCallableSelectionsInProgress.remove(fn);
		throw error;
	} catch (error:String) {
		memo.emittedCallableSelectionsInProgress.remove(fn);
		throw error;
	}
	memo.emittedCallableSelectionsInProgress.remove(fn);
	if (!externalAnalysis)
		memo.emittedCallableContracts.set(fn, result);
	return result;
}

/** Keep helper eligibility in its existing predicates while selecting the shared signature owner. */
private function selectStrategy(fn:HxFunctionDecl, owner:HxClassDecl, lookup:CppClassLookup):CppCallableStrategy {
	if (Core.isUtestAssertCallableHook(fn, owner, lookup))
		return UtestHook(HxFunctionDecl.getName(fn) == "createEvent");
	if (Core.isRttiMetaHelper(fn, owner))
		return RttiMeta;
	if (Core.isAssertPolymorphicStringifyHelper(fn, owner))
		return AssertStringify;
	if (Core.isAssertPolymorphicSameAsHelper(fn, owner))
		return AssertSameAs(Core.isAssertPolymorphicSameAsFastSignature(fn));
	if (Core.isAssertPolymorphicSameHelper(fn, owner))
		return AssertSame(Core.isAssertPolymorphicSameFastSignature(fn));
	if (Core.isUtestEqHelper(fn, owner))
		return UtestEq;
	if (owner != null
		&& Core.isUnitTestBaseSupportClass(owner, lookup)
		&& (HxFunctionDecl.getName(fn) == "exc" || HxFunctionDecl.getName(fn) == "unspec"))
		return UtestFunction;
	if (owner != null
		&& Core.isUnitTestBaseSupportClass(owner, lookup)
		&& (HxFunctionDecl.getName(fn) == "t" || HxFunctionDecl.getName(fn) == "f"))
		return UtestValue;
	if (owner != null && Core.isUnitTestBaseSupportClass(owner, lookup) && HxFunctionDecl.getName(fn) == "allow")
		return UtestAllow;
	final neutral = Core.neutralSupportFastSignature(fn, owner, lookup);
	if (neutral != null)
		return UtestNeutral(neutral);
	if (Core.isLambdaHasHelper(fn, owner))
		return LambdaHas;
	if (owner != null && Core.isSerializerRunHelper(fn, owner))
		return SerializerRun;
	if (Core.isPolymorphicIsOfTypeHelper(fn))
		return PolymorphicIsOfType;
	if (Core.isTypeErasedValueHelper(fn, owner))
		return TypeErasedValue;
	return Ordinary;
}

/** Keep generic identity independent of name allocation and preserve source parameter order. */
private function build(fn:HxFunctionDecl, owner:HxClassDecl, projection:Null<TypedBackendFunctionProjection>, strategy:CppCallableStrategy, returnType:String,
		scope:CppRenderScope):CppEmittedCallableContract {
	final generics = new Array<CppCallableGeneric>();
	final classParams = owner == null ? [] : Core.genericClassTemplateParams(owner);
	for (index in 0...classParams.length)
		generics.push(new CppCallableGeneric(ClassParameter(owner), index, Core.sanitizeIdentifier(classParams[index])));
	final functionParams = Core.genericFunctionTypeParams(fn);
	for (index in 0...functionParams.length)
		generics.push(new CppCallableGeneric(FunctionParameter(fn), index, Core.cppTypeParamName(functionParams[index], scope)));
	final templates = new Array<CppCallableGeneric>();
	final sourceSignature = switch (strategy) {
		case Ordinary | UtestNeutral(_) | UtestFunction: true;
		case _: false;
	};
	final iterableGeneric = strategy == LambdaHas ? declaredCollectionElementGeneric(fn, generics, 1,
		0) : strategy == UtestAllow ? declaredCollectionElementGeneric(fn, generics, 0, 1) : null;
	if (iterableGeneric != null) {
		templates.push(iterableGeneric);
	} else if (!sourceSignature) {
		final occupied = new haxe.ds.StringMap<Bool>();
		for (generic in generics)
			occupied.set(generic.cppName, true);
		final preferred = switch (strategy) {
			case PolymorphicIsOfType: ["TValue", "TType"];
			case AssertStringify | RttiMeta | SerializerRun: ["T"];
			case TypeErasedValue: ["TValue"];
			case UtestValue | UtestAllow: HxFunctionDecl.getArgs(fn).length == 0 ? [] : ["TValue"];
			case LambdaHas: ["A"];
			case AssertSameAs(_): ["TExpected", "TValue", "TStatus"];
			case AssertSame(_) | UtestEq: ["TExpected", "TValue"];
			case Ordinary | UtestNeutral(_) | UtestFunction | UtestHook(_): [];
		};
		for (index in 0...preferred.length) {
			var name = preferred[index];
			var suffix = 2;
			while (occupied.exists(name))
				name = preferred[index] + "_" + suffix++;
			occupied.set(name, true);
			templates.push(new CppCallableGeneric(SyntheticParameter(fn), index, name));
		}
	} else {
		for (name in Core.emittedFunctionTypeParams(fn, returnType, scope))
			for (generic in generics)
				if (generic.cppName == name)
					switch (generic.owner) {
						case FunctionParameter(_):
							templates.push(generic);
						case _:
					}
	}
	final args = HxFunctionDecl.getArgs(fn);
	final bindings = projection == null ? [] : projection.getParameters();
	final parameters = new Array<CppCallableParameter>();
	final sameAs = switch (strategy) {
		case AssertSameAs(_): true;
		case _: false;
	};
	final same = switch (strategy) {
		case AssertSame(_): true;
		case _: false;
	};
	for (index in 0...args.length) {
		var type = switch (strategy) {
			case Ordinary: Core.cppFunctionArgType(args[index], scope);
			case UtestHook(event): index == 0 ? (event ? "std::function<void(std::any)>" : "std::optional<std::function<void()>>") : index == 1 ? "std::optional<int>" : Core.cppFunctionArgType(args[index],
					scope);
			case UtestFunction: index == 0 ? "std::function<void()>" : index == 1 ? "std::optional<PosInfos>" : Core.cppFunctionArgType(args[index], scope);
			case UtestNeutral(fast): fast ? Core.fastNeutralArgType(args[index],
					Core.fastUtestAssertType(HxFunctionArg.getTypeHint(args[index]), HxFunctionArg.getDefaultValue(args[index]),
						true)) : Core.cppFunctionArgType(args[index], scope);
			case LambdaHas:
				final iterable = "std::vector<" + templates[0].cppName + ">";
				index == 0 ? iterable : "typename " + iterable + "::value_type";
			case AssertSameAs(fast):
				index < 3 ? templates[index].cppName : fast ? "double" : Core.cppFunctionArgType(args[index], scope);
			case AssertSame(fast):
				index < 2 ? templates[index].cppName : fast ? [
					"std::optional<bool>",
					"std::optional<std::string>",
					"std::optional<double>",
					"std::optional<PosInfos>"
				][index - 2] : Core.cppFunctionArgType(args[index], scope);
			case UtestEq:
				index < 2 ? templates[index].cppName : index == 2 ? "std::optional<PosInfos>" : Core.cppFunctionArgType(args[index], scope);
			case UtestValue: index == 0 ? templates[0].cppName : index == 1 ? "std::optional<PosInfos>" : Core.cppFunctionArgType(args[index], scope);
			case UtestAllow: index == 0 ? templates[0].cppName : index == 1 ? "std::vector<"
				+ templates[0].cppName + ">" : index == 2 ? "std::optional<PosInfos>" : Core.cppFunctionArgType(args[index], scope);
			case _: templates[index].cppName;
		};
		var passing = sourceSignature || strategy == SerializerRun || (strategy == LambdaHas && index == 1) ? Value : ConstReference;
		final hook = switch (strategy) {
			case UtestHook(_): true;
			case _: false;
		};
		if (hook)
			passing = Value;
		if (sameAs)
			passing = index == 2 ? MutableReference : index < 2 ? ConstReference : Value;
		if (same || strategy == UtestEq)
			passing = index < 2 ? ConstReference : Value;
		if (strategy == UtestValue || strategy == UtestAllow)
			passing = index == 0 ? ConstReference : Value;
		final sourceTyped = sourceSignature
			|| hook
			|| (sameAs && index >= 3)
			|| ((same || strategy == UtestEq || strategy == UtestAllow) && index >= 2)
			|| (strategy == UtestValue && index >= 1);
		if (sourceTyped && StringTools.endsWith(type, "&")) {
			passing = StringTools.startsWith(type, "const ") ? ConstReference : MutableReference;
			type = StringTools.trim(type.substr(passing == ConstReference ? 6 : 0, type.length - (passing == ConstReference ? 7 : 1)));
		}
		final dependencies = !sourceTyped ? [templates[strategy == LambdaHas || strategy == UtestAllow ? 0 : index]] : [
			for (generic in generics)
				if (Core.cppTypeTextMentionsParam(type, generic.cppName)) generic
		];
		final kind = dependencies.length == 0 ? Fixed : dependencies.length == 1
			&& dependencies[0].cppName == type ? IndependentDeduced : Dependent;
		parameters.push(new CppCallableParameter({
			declaration: args[index],
			binding: projection == null ? null : bindings[index],
			slot: index,
			cppType: type,
			kind: kind,
			passing: passing,
			generics: dependencies,
			defaultEmission: switch (strategy) {
				case Ordinary: SourceDefault;
				case UtestFunction | UtestValue: index == 0 ? OmitDefault : index == 1 ? TargetDefault("std::nullopt") : SourceDefault;
				case UtestAllow: index < 2 ? OmitDefault : index == 2 ? TargetDefault("std::nullopt") : SourceDefault;
				case UtestNeutral(fast):
					if (!fast) SourceDefault; else {
						final suffix = Core.fastNeutralArgDefaultSuffix(args[index], type);
						suffix.length == 0 ? OmitDefault : TargetDefault(suffix.substr(3));
					}
				case AssertSameAs(fast): index >= 3 && !fast ? SourceDefault : OmitDefault;
				case AssertSame(fast): index < 2 ? OmitDefault : fast ? TargetDefault("std::nullopt") : SourceDefault;
				case UtestEq: index < 2 ? OmitDefault : index == 2 ? TargetDefault("std::nullopt") : SourceDefault;
				case _: OmitDefault;
			}
		}));
	}
	final fixedSymbols = [for (generic in generics.concat(templates)) generic.cppName];
	final trailingParameters = new Array<CppCallableTrailingParameter>();
	if (strategy == UtestEq && args.length == 2) {
		final position = new CppCallableTrailingParameter({
			slot: 2,
			cppName: "__hxhx_eq_pos",
			cppType: "std::optional<PosInfos>",
			defaultExpression: "std::nullopt"
		});
		trailingParameters.push(position);
		fixedSymbols.push(position.cppName);
	}
	if ((strategy == UtestFunction || strategy == UtestValue || strategy == UtestAllow)
		&& args.length < (strategy == UtestAllow ? 3 : 2)) {
		final position = new CppCallableTrailingParameter({
			slot: args.length,
			cppName: "__hxhx_wrapper_pos",
			cppType: "std::optional<PosInfos>",
			defaultExpression: "std::nullopt"
		});
		trailingParameters.push(position);
		fixedSymbols.push(position.cppName);
	}
	switch (strategy) {
		case SerializerRun:
			fixedSymbols.push("s");
		case LambdaHas:
			fixedSymbols.push("x");
		case AssertSameAs(_):
			for (name in ["__hxhx_status", "__hxhx_same_as_approx"])
				fixedSymbols.push(name);
		case AssertSame(_):
			for (name in [
				"__hxhx_status",
				"__hxhx_same_status",
				"__hxhx_recursive_opt",
				"__hxhx_msg_opt",
				"__hxhx_approx_opt",
				"__hxhx_pos_opt"
			])
				fixedSymbols.push(name);
		case TypeErasedValue:
			for (name in [
				"__hxhx_class_type",
				"__hxhx_value_type",
				"__hxhx_enum_value",
				"__hxhx_enum_type"
			])
				fixedSymbols.push(name);
		case _:
	}
	return new CppEmittedCallableContract({
		owner: owner,
		declaration: fn,
		projection: projection,
		strategy: strategy,
		returnType: returnType,
		parameters: parameters,
		trailingParameters: trailingParameters,
		templates: templates,
		fixedSymbols: fixedSymbols
	});
}

/** Preserve the source relationship when both iterable and element name one exact function generic. */
private function declaredCollectionElementGeneric(fn:HxFunctionDecl, generics:Array<CppCallableGeneric>, elementIndex:Int,
		collectionIndex:Int):Null<CppCallableGeneric> {
	final args = HxFunctionDecl.getArgs(fn);
	if (args.length <= elementIndex || args.length <= collectionIndex)
		return null;
	final element = Core.genericTypeParamName(HxFunctionArg.getTypeHint(args[elementIndex]));
	if (element.length == 0 || Core.genericTypeHintArg(HxFunctionArg.getTypeHint(args[collectionIndex])) != element)
		return null;
	final slot = Core.genericFunctionTypeParams(fn).indexOf(element);
	if (slot < 0)
		return null;
	for (generic in generics)
		switch (generic.owner) {
			case FunctionParameter(owner) if (owner == fn && generic.slot == slot):
				return generic;
			case _:
		}
	return null;
}
