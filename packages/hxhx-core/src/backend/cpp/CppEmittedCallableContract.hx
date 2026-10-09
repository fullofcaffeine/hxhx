package backend.cpp;

/** The selected renderer, independent of which caller first requests its types. */
enum CppCallableStrategy {
	Ordinary;
	PolymorphicIsOfType;
	AssertStringify;
	RttiMeta;
	SerializerRun;
	TypeErasedValue;
	LambdaHas;
	AssertSameAs(fast:Bool);
	AssertSame(fast:Bool);
	UtestEq;
	UtestNeutral(fast:Bool);
	UtestFunction;
	UtestValue;
	UtestAllow;
	UtestHook(event:Bool);
}

/** A trailing target-only argument has no source binding and cannot satisfy source arity. */
class CppCallableTrailingParameter {
	public final slot:Int;
	public final cppName:String;
	public final cppType:String;
	public final defaultExpression:String;

	public function new(input:{
		slot:Int,
		cppName:String,
		cppType:String,
		defaultExpression:String
	}) {
		if (input.slot < 0 || input.cppName.length == 0 || input.cppType.length == 0 || input.defaultExpression.length == 0)
			throw "C++ trailing parameter requires a slot, name, representation, and default";
		slot = input.slot;
		cppName = input.cppName;
		cppType = input.cppType;
		defaultExpression = input.defaultExpression;
	}
}

/** Source omission and the default published by a target helper are distinct contracts. */
enum CppCallableDefault {
	SourceDefault;
	OmitDefault;
	TargetDefault(expression:String);
}

/** Exact declaration ownership distinguishes same-spelled target type parameters. */
enum CppCallableGenericOwner {
	ClassParameter(owner:HxClassDecl);
	FunctionParameter(owner:HxFunctionDecl);
	SyntheticParameter(owner:HxFunctionDecl);
}

/** A generic's declaration and slot are its identity; its C++ name is only output. */
class CppCallableGeneric {
	public final owner:CppCallableGenericOwner;
	public final slot:Int;
	public final cppName:String;

	public function new(owner:CppCallableGenericOwner, slot:Int, cppName:String) {
		if (owner == null || slot < 0 || cppName == null || cppName.length == 0)
			throw "C++ callable generic requires an owner, slot, and output name";
		this.owner = owner;
		this.slot = slot;
		this.cppName = cppName;
	}
}

/** A deduced carrier transports storage; a dependent type needs its generic bindings. */
enum CppCallableParameterKind {
	Fixed;
	IndependentDeduced;
	Dependent;
}

/** Parameter passing is distinct from the representation stored in the function body. */
enum CppCallablePassingMode {
	Value;
	ConstReference;
	MutableReference;
}

/**
	Immutable facts for one exact source argument and its emitted parameter slot.
	C++ type text belongs to this target boundary. Generic authority comes from
	declaration-owned bindings, never from a target name's spelling.
 */
class CppCallableParameter {
	public final declaration:HxFunctionArg;
	public final binding:Null<TypedBackendLocalProjection>;
	public final slot:Int;
	public final cppType:String;
	public final kind:CppCallableParameterKind;
	public final passing:CppCallablePassingMode;
	public final optional:Bool;
	public final rest:Bool;
	public final defaultValue:HxDefaultValue;

	/** Whether the emitted declaration can supply a default; source omission facts remain separate. */
	public final emitDefault:Bool;

	public final defaultEmission:CppCallableDefault;

	final generics:Array<CppCallableGeneric>;

	public function new(input:{
		declaration:HxFunctionArg,
		binding:Null<TypedBackendLocalProjection>,
		slot:Int,
		cppType:String,
		kind:CppCallableParameterKind,
		passing:CppCallablePassingMode,
		generics:Array<CppCallableGeneric>,
		?defaultEmission:CppCallableDefault
	}) {
		if (input.declaration == null || input.slot < 0 || input.cppType == null || input.cppType.length == 0)
			throw "C++ callable parameter requires an exact argument and representation";
		generics = input.generics.copy();
		switch (input.kind) {
			case Fixed:
				if (generics.length != 0)
					throw "C++ fixed callable parameter cannot own generic dependencies";
			case IndependentDeduced:
				if (generics.length != 1 || generics[0].cppName != input.cppType)
					throw "C++ deduced callable parameter requires one exact generic binding";
			case Dependent:
				if (generics.length == 0)
					throw "C++ dependent callable parameter requires generic bindings";
		}
		declaration = input.declaration;
		binding = input.binding;
		slot = input.slot;
		cppType = input.cppType;
		kind = input.kind;
		passing = input.passing;
		optional = HxFunctionArg.getIsOptional(declaration);
		rest = HxFunctionArg.getIsRest(declaration);
		defaultValue = HxFunctionArg.getDefaultValue(declaration);
		defaultEmission = input.defaultEmission == null ? SourceDefault : input.defaultEmission;
		emitDefault = defaultEmission != OmitDefault;
	}

	public function getGenerics():Array<CppCallableGeneric>
		return generics.copy();

	public function signatureType():String {
		return switch (passing) {
			case Value: cppType;
			case ConstReference: "const " + cppType + "&";
			case MutableReference: cppType + "&";
		};
	}
}

/**
	One declaration's selected C++ signature shared by rendering and call adaptation.
	Production records retain the exact typed projection and ordered parameter
	bindings. Class-only syntax probes have no projection and cannot supply one
	to a production lookup. Arrays are copied; output-name allocators and caller
	substitutions never enter this request-owned record.
 */
@:allow(backend.cpp.CppEmittedCallableSelection)
class CppEmittedCallableContract {
	public final owner:HxClassDecl;
	public final declaration:HxFunctionDecl;
	public final projection:Null<TypedBackendFunctionProjection>;
	public final bodyRevision:String;
	public final strategy:CppCallableStrategy;
	public final returnType:String;

	final parameters:Array<CppCallableParameter>;
	final trailingParameters:Array<CppCallableTrailingParameter>;
	final templates:Array<CppCallableGeneric>;
	final fixedSymbols:Array<String>;

	function new(input:{
		owner:HxClassDecl,
		declaration:HxFunctionDecl,
		projection:Null<TypedBackendFunctionProjection>,
		strategy:CppCallableStrategy,
		returnType:String,
		parameters:Array<CppCallableParameter>,
		trailingParameters:Array<CppCallableTrailingParameter>,
		templates:Array<CppCallableGeneric>,
		fixedSymbols:Array<String>
	}) {
		owner = input.owner;
		declaration = input.declaration;
		projection = input.projection;
		strategy = input.strategy;
		returnType = input.returnType;
		if (declaration == null || returnType == null || returnType.length == 0)
			throw "C++ callable contract requires a declaration and result representation";
		if (projection != null && projection.getDeclaration() != declaration)
			throw "C++ callable contract has a foreign function projection";
		bodyRevision = projection == null ? "" : projection.getBodyRevision();
		parameters = input.parameters.copy();
		trailingParameters = input.trailingParameters.copy();
		templates = input.templates.copy();
		fixedSymbols = input.fixedSymbols.copy();
		final args = HxFunctionDecl.getArgs(declaration);
		final bindings = projection == null ? [] : projection.getParameters();
		if (args.length != parameters.length)
			throw "C++ callable contract parameter count differs from its declaration";
		for (index in 0...trailingParameters.length)
			if (trailingParameters[index].slot != parameters.length + index)
				throw "C++ trailing parameters must follow all exact source parameters";
		for (index in 0...parameters.length) {
			final parameter = parameters[index];
			if (parameter.slot != index
				|| parameter.declaration != args[index]
				|| parameter.binding != (projection == null ? null : bindings[index]))
				throw "C++ callable contract lost an exact ordered parameter binding";
		}
	}

	public function getParameters():Array<CppCallableParameter>
		return parameters.copy();

	public function getTrailingParameters():Array<CppCallableTrailingParameter>
		return trailingParameters.copy();

	public function getTemplates():Array<CppCallableGeneric>
		return templates.copy();

	public function getFixedSymbols():Array<String>
		return fixedSymbols.copy();

	public function getParameterTypes():Array<String>
		return [for (parameter in parameters) parameter.cppType];

	/** Assignable callbacks store the same parameter passing modes and result as their declarations. */
	public function storageType():String {
		final types = [for (parameter in parameters) parameter.signatureType()];
		for (parameter in trailingParameters)
			types.push(parameter.cppType);
		return "std::function<" + returnType + "(" + types.join(", ") + ")>";
	}

	/** An empty initializer can omit its type only when other parameters deduce every exact dependency. */
	public function hasIndependentDeductionFor(parameter:CppCallableParameter):Bool {
		if (parameters.indexOf(parameter) < 0)
			throw "C++ generic deduction received a foreign parameter";
		if (parameter.kind != Dependent)
			return false;
		for (generic in parameter.getGenerics()) {
			var found = false;
			for (other in parameters)
				if (other != parameter && other.kind == IndependentDeduced && other.getGenerics().indexOf(generic) >= 0)
					found = true;
			if (!found)
				return false;
		}
		return true;
	}

	public function requireParameter(argument:HxFunctionArg):CppCallableParameter {
		for (parameter in parameters)
			if (parameter.declaration == argument)
				return parameter;
		throw "C++ callable contract received a foreign function parameter";
	}

	/** Exact object ownership prevents cache reuse across requests or same-named functions. */
	public function assertOwner(owner:HxClassDecl, declaration:HxFunctionDecl, projection:Null<TypedBackendFunctionProjection>):Void {
		if (this.owner != owner
			|| this.declaration != declaration
			|| this.projection != projection
			|| (projection != null && bodyRevision != projection.getBodyRevision()))
			throw "C++ callable contract belongs to another declaration or body revision";
	}
}
