package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
#if macro
import haxe.macro.Type;
import haxe.macro.TypeTools;
#end

/** Native storage known at a generic method boundary, before syntax generation. */
enum OcamlGenericValueShape {
	/** A method parameter already stored as Obj.t; identity includes its declaring scope. */
	Erased(parameterId:String);

	Integer;
	Boolean;
	Text(nullable:Bool);
	NullableInteger;
	NullableBoolean;

	/** Exact registered record identity; null uses the same native reference carrier. */
	NominalValue(typeId:String, representationId:String, nullable:Bool);

	ArrayValue(element:OcamlGenericValueShape);
	FunctionValue(arguments:Array<OcamlGenericValueShape>, result:OcamlGenericValueShape);
	EffectOnly;
}

/** Directional operations; function arguments flow opposite to the function result. */
enum OcamlGenericValueConversion {
	Identity;
	BoxValue;
	UnboxValue;
	BoxBoolean;
	UnboxBoolean;
	BoxNullableBoolean;
	UnboxNullableBoolean;
	AdaptFunction(arguments:Array<OcamlGenericValueConversion>, result:OcamlGenericValueConversion);
}

/**
	Selects conversions between a generic method declaration and one instantiation.

	Ordinary generic methods use Obj.t for their own type parameters. A callback
	with a concrete result therefore needs a function adapter, not a cast of the
	whole closure. This module decides both directions from typed Haxe values.
	The call owner remains responsible for exact occurrence identity, evaluation
	order, runtime helper ownership, and consuming the decision before syntax.

	The admitted value shapes are deliberately explicit. An unresolved type,
	foreign runtime type, enum, or substituted container layout needs its own
	representation proof before this boundary can select a conversion.
**/

#if macro
/** Method type parameters use qualified identities, never macro wrapper identity. */
function parameterId(type:Type):Null<String> {
	return switch (TypeTools.follow(type)) {
		case TInst(reference, []):
			final declaration = reference.get();
			switch (declaration.kind) {
				case KTypeParameter(_): [declaration.module, declaration.pack.join("."), declaration.name].join("|");
				case _: null;
			}
		case _: null;
	}
}

/** Classifies storage without following away the distinction between String and Null<String>. */
function shape(type:Type, ?nominalProof:String->Null<String>):Null<OcamlGenericValueShape> {
	final parameter = parameterId(type);
	if (parameter != null)
		return Erased(parameter);
	return switch (type) {
		case TLazy(resolve): shape(resolve(), nominalProof);
		case TMono(reference):
			final resolved = reference.get();
			resolved == null ? null : shape(resolved, nominalProof);
		case TType(reference, parameters):
			final declaration = reference.get();
			shape(TypeTools.applyTypeParameters(declaration.type, declaration.params, parameters), nominalProof);
		case TAbstract(reference, parameters):
			final declaration = reference.get();
			if (declaration.pack.length != 0) null else switch ([declaration.name, parameters]) {
				case ["Int", []]: Integer;
				case ["Bool", []]: Boolean;
				case ["Void", []]: EffectOnly;
				case ["Null", [inner]]:
					switch (shape(inner, nominalProof)) {
						case Text(_): Text(true);
						case Integer: NullableInteger;
						case Boolean: NullableBoolean;
						case NominalValue(typeId, proof, _): NominalValue(typeId, proof, true);
						case _: null;
					}
				case _: null;
			}
		case TInst(reference, parameters):
			final declaration = reference.get();
			final typeId = (declaration.pack ?? []).concat([declaration.name]).join(".");
			final proof = nominalProof == null ? null : nominalProof(typeId);
			if (proof != null && parameters.length == 0 && !declaration.isExtern && !declaration.isInterface && !declaration.meta.has(":native")
				&& declaration.params.length == 0) {
				NominalValue(typeId, proof, false);
			} else if (declaration.pack.length != 0) null else switch ([declaration.module, declaration.name, parameters]) {
				case ["String", "String", []]: Text(false);
				case ["Array", "Array", [element]]: final selected = shape(element,
						nominalProof); selected == null || !isArrayElement(selected) ? null : ArrayValue(selected);
				case _: null;
			}
		case TFun(arguments, result): final selectedArguments:Array<OcamlGenericValueShape> = []; var supported = true; for (argument in arguments) {
				final selected = shape(argument.t, nominalProof);
				if (argument.opt || selected == null || selected == EffectOnly)
					supported = false;
				else
					selectedArguments.push(selected);
			} final selectedResult = shape(result,
				nominalProof); !supported || selectedResult == null ? null : FunctionValue(selectedArguments, selectedResult);
		case _: null;
	}
}
#end

/**
	Checks a declaration against one instantiated type and records each substitution.

	The caller shares the substitution map across all parameters and the result.
	This rejects inconsistent instantiations and a different method's same-named T.
	Containers cannot change their element storage merely because a leaf is generic.
**/
function matchInstantiation(declared:OcamlGenericValueShape, instantiated:OcamlGenericValueShape, ownedParameterIds:Array<String>,
		substitutions:Map<String, String>):Bool {
	return switch ([declared, instantiated]) {
		case [Erased(parameter), _]:
			if (ownedParameterIds.indexOf(parameter) < 0 || instantiated == EffectOnly) {
				false;
			} else {
				final identity = shapeId(instantiated);
				final previous = substitutions.get(parameter);
				if (previous != null && previous != identity)
					false
				else {
					substitutions.set(parameter, identity);
					true;
				}
			}
		case [
			FunctionValue(declaredArguments, declaredResult),
			FunctionValue(actualArguments, actualResult)
		]: declaredArguments.length == actualArguments.length && allArgumentsMatch(declaredArguments, actualArguments, ownedParameterIds,
			substitutions) && matchInstantiation(declaredResult, actualResult, ownedParameterIds, substitutions);
		case _: shapeId(declared) == shapeId(instantiated);
	}
}

private function allArgumentsMatch(declared:Array<OcamlGenericValueShape>, actual:Array<OcamlGenericValueShape>, owned:Array<String>,
		substitutions:Map<String, String>):Bool {
	for (index in 0...declared.length)
		if (!matchInstantiation(declared[index], actual[index], owned, substitutions))
			return false;
	return true;
}

/** Selects a conversion only after the call owner verifies one coherent instantiation. */
function crossing(source:OcamlGenericValueShape, destination:OcamlGenericValueShape):Null<OcamlGenericValueConversion> {
	if (shapeId(source) == shapeId(destination))
		return Identity;
	return switch ([source, destination]) {
		case [Erased(_), Erased(_)], [NullableInteger, Erased(_)], [Erased(_), NullableInteger]: Identity;
		case [NullableBoolean, Erased(_)]: BoxNullableBoolean;
		case [Erased(_), NullableBoolean]: UnboxNullableBoolean;
		case [Boolean, Erased(_)]: BoxBoolean;
		case [Erased(_), Boolean]: UnboxBoolean;
		case [Integer | Text(_) | ArrayValue(_) | NominalValue(_, _, _), Erased(_)]: BoxValue;
		case [Erased(_), Integer | Text(_) | ArrayValue(_) | NominalValue(_, _, _)]: UnboxValue;
		case [
			FunctionValue(sourceArguments, sourceResult),
			FunctionValue(destinationArguments, destinationResult)
		]:
			if (sourceArguments.length != destinationArguments.length) null else {
				final arguments:Array<OcamlGenericValueConversion> = [];
				var supported = true;
				for (index in 0...sourceArguments.length) {
					final argument = crossing(destinationArguments[index], sourceArguments[index]);
					if (argument == null)
						supported = false
					else
						arguments.push(argument);
				}
				final result = crossing(sourceResult, destinationResult);
				!supported
				|| result == null ? null : AdaptFunction(arguments, result);
			}
		case _: null;
	}
}

/** Stable shape identity excludes callback parameter names. */
function shapeId(value:OcamlGenericValueShape):String {
	return switch (value) {
		case Erased(parameter): 'parameter:$parameter';
		case Integer: "Int";
		case Boolean: "Bool";
		case Text(nullable): nullable ? "Null<String>" : "String";
		case NullableInteger: "Null<Int>";
		case NullableBoolean: "Null<Bool>";
		case NominalValue(typeId, representationId, nullable): 'class:${typeId}:${representationId}:${nullable}';
		case ArrayValue(element): 'Array<${shapeId(element)}>';
		case FunctionValue(arguments, result): '(${arguments.map(shapeId).join(",")})->${shapeId(result)}';
		case EffectOnly: "Void";
	}
}

private function isArrayElement(value:OcamlGenericValueShape):Bool {
	return switch (value) {
		case Integer, Boolean, Text(_), NullableInteger, NullableBoolean, ArrayValue(_): true;
		case _: false;
	}
}
#end
