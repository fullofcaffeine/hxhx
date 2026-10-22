package backend.cpp;

import backend.cpp.CppManagedSourceCall.CppManagedSourceCallInput;

/** The six standard operations keep their declaration signatures and physical result categories. */
private typedef ReflectionOperation = {
	final name:String;
	final argument:TyType;
	final result:TyType;
	final parameters:Array<TyTypeParameterId>;
}

/**
	Bind standard reflection to this program's existing descriptor owners.
	Haxe selects declarations, public names, core representations, and operand
	transfers. The native primitive only observes those selected physical values.
	The lookup tables refer to descriptors; they never create a second identity.
 */
class CppManagedReflection {
	final program:CppTypedProgramProjection;
	final classes:CppManagedClassStorage;
	final enums:CppManagedEnumDescriptors;
	var enabled:Bool = false;
	var requiresCoreClasses:Bool = false;

	public function new(program:CppTypedProgramProjection, classes:CppManagedClassStorage, enums:CppManagedEnumDescriptors) {
		if (program == null || classes == null || enums == null)
			throw "managed reflection requires program-owned class and enum descriptors";
		this.program = program;
		this.classes = classes;
		this.enums = enums;
	}

	static function operation(name:String):Null<ReflectionOperation> {
		final opaque = TyType.fromHintText("Dynamic");
		final text = TyType.fromHintText("String");
		final classType = TyType.nominal(new TyNominalTypeId("Class"), [opaque]);
		final enumType = TyType.nominal(new TyNominalTypeId("Enum"), [opaque]);
		final parameter = TyTypeParameterId.method(new TyNominalTypeId("Type"), true, "getClass", 0, 0, "T");
		return switch name {
			case "getClass": {
					name: name,
					argument: TyType.typeParameter(parameter),
					result: TyType.nominal(new TyNominalTypeId("Class"), [TyType.typeParameter(parameter)]),
					parameters: [parameter]
				};
			case "getEnum": {
					name: name,
					argument: TyType.nominal(new TyNominalTypeId("EnumValue"), []),
					result: enumType,
					parameters: []
				};
			case "getClassName": {
					name: name,
					argument: classType,
					result: text,
					parameters: []
				};
			case "getEnumName": {
					name: name,
					argument: enumType,
					result: text,
					parameters: []
				};
			case "resolveClass": {
					name: name,
					argument: text,
					result: classType,
					parameters: []
				};
			case "resolveEnum": {
					name: name,
					argument: text,
					result: enumType,
					parameters: []
				};
			case _: null;
		};
	}

	/** Source names alone cannot bind an operation; the complete declaration key must match. */
	public static function owns(declaration:TyDeclarationInfo):Bool {
		if (declaration == null || declaration.getModulePath() != "Type" || declaration.getOwner().getCanonicalName() != "Type")
			return false;
		final selected = operation(declaration.getSignature().getName());
		return selected != null
			&& declaration.getIdentity().getCanonicalKey() == "Type#static:"
				+ selected.name
				+ "(required:"
				+ selected.argument.getSemanticKey()
				+ ")->"
				+ selected.result.getSemanticKey()
				+ "#0";
	}

	/** Recheck mutable signatures and generic binders before every use of the native binding. */
	public static function requireDeclaration(declaration:TyDeclarationInfo):Void {
		if (!owns(declaration))
			throw "managed reflection requires an exact standard Type declaration";
		final selected = operation(declaration.getSignature().getName());
		final signature = declaration.getSignature();
		final parameters = declaration.getTypeParameterIds();
		if (!declaration.getIsStatic()
			|| declaration.getIsDynamic()
			|| parameters.length != selected.parameters.length
			|| signature.getArgs().length != 1
			|| signature.getArgOptional().length != 1
			|| signature.getArgRest().length != 1
			|| signature.getArgOptional()[0]
			|| signature.getArgRest()[0]
			|| signature.getArgs()[0].getSemanticKey() != selected.argument.getSemanticKey()
			|| signature.getReturnType().getSemanticKey() != selected.result.getSemanticKey())
			throw "managed reflection requires its exact standard signature";
		for (slot in 0...parameters.length) {
			if (!parameters[slot].equals(selected.parameters[slot]))
				throw "managed reflection requires its exact generic parameter";
			final bounds = declaration.getResolvedTypeParameterConstraints().get(parameters[slot].getCanonicalKey());
			if (bounds != null && bounds.length != 0)
				throw "managed reflection generic parameter must be unconstrained";
		}
	}

	/** Only the exact current extern declaration can authorize the native operation. */
	public function select(declaration:TyDeclarationInfo):Void {
		requireDeclaration(declaration);
		program.assertPlanningCurrent();
		final owner = program.requireClass(program.requireClassIdentity("Type"));
		if (!owner.requireSemanticFacts().getIsExtern()
			|| declaration.getHasBody()
			|| owner.getFunctions().filter(fn -> fn.requireSemanticDeclaration() == declaration).length != 1)
			throw "managed reflection belongs to another program or authored declaration";
		enabled = true;
		if (declaration.getSignature().getName() == "getClass")
			requiresCoreClasses = true;
	}

	/** The generic getClass result retains the exact source operand type in Class<T>. */
	public function resultType(declaration:TyDeclarationInfo, arguments:Array<HxExpr>, valueType:HxExpr->TyType, callerClasses:CppManagedClassStorage):TyType {
		if (callerClasses != classes)
			throw "managed reflection belongs to another caller descriptor plan";
		select(declaration);
		if (arguments.length != 1)
			throw "managed reflection requires one evaluated operand";
		final operand = valueType(arguments[0]);
		CppManagedClosureAbi.assertComplete(operand);
		return declaration.getSignature()
			.getName() == "getClass" ? TyType.nominal(new TyNominalTypeId("Class"), [operand]) : declaration.getSignature()
			.getReturnType();
	}

	/** Evaluate the operand once and retain it across observation and result publication. */
	public function render(declaration:TyDeclarationInfo, input:CppManagedSourceCallInput, indent:String):Array<String> {
		resultType(declaration, input.arguments, input.valueType, input.classes);
		final selected = operation(declaration.getSignature().getName());
		if (selected.name != "getClass" && !input.acceptsStoredTransfer(input.arguments[0], selected.argument))
			throw "managed reflection operand requires its checked standard parameter: " + selected.name;
		final root = "hxhx_reflection_" + input.prefix + (input.destination == null ? "discarded" : input.destination);
		final value = root + ".get()";
		final classTable = "hxhx_reflection_classes.data(), hxhx_reflection_classes.size()";
		final enumTable = "hxhx_reflection_enums.data(), hxhx_reflection_enums.size()";
		final call = "hxhx::managed::" + switch selected.name {
			case "getClass": "reflectionClass(" + value + ", hxhx_reflection_string, hxhx_reflection_array)";
			case "getEnum": "reflectionEnum(" + value + ")";
			case "getClassName": "reflectionClassName(" + value + ", " + classTable + ")";
			case "getEnumName": "reflectionEnumName(" + value + ", " + enumTable + ")";
			case "resolveClass": "reflectionResolveClass(" + input.heap + ", " + value + ", " + classTable + ")";
			case "resolveEnum": "reflectionResolveEnum(" + input.heap + ", " + value + ", " + enumTable + ")";
			case _: throw "unselected reflection operation";
		};
		final lines = [
			indent + "{",
			indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
		];
		for (line in input.renderValue(input.arguments[0], root, indent + "  "))
			lines.push(line);
		lines.push(indent + "  " + (input.destination == null ? "(void)" + call : input.destination + ".set(" + call + ")") + ";");
		lines.push(indent + "}");
		return lines;
	}

	/**
		Select names from shared semantic facts, then refer to the existing descriptors.
		Core String and Array use explicit shared runtime kinds. An arbitrary extern
		name never becomes a reflected class merely because it has a native binding.
	 */
	public function renderTables():String {
		if (!enabled)
			return "";
		program.assertPlanningCurrent();
		final classEntries = new Array<String>();
		final enumEntries = new Array<String>();
		final classNames = new haxe.ds.StringMap<Bool>();
		final enumNames = new haxe.ds.StringMap<Bool>();
		var stringSymbol = "nullptr";
		var arraySymbol = "nullptr";
		for (module in program.getModules())
			for (owner in module.projection.getClasses()) {
				final facts = owner.requireSemanticFacts();
				final core = switch facts.getClassIdentity() {
					case "String": new TypedRuntimeTypeTarget(StringCore);
					case "Array": new TypedRuntimeTypeTarget(ArrayCore);
					case _: null;
				};
				if (facts.getIsExtern() && core == null)
					continue;
				switch facts.getNominalKind() {
					case ClassInstance:
						final name = core == null ? facts.requirePublicReflectionName() : core.requireCoreReflectionName();
						if (classNames.exists(name))
							throw "managed reflection repeats a public class name: " + name;
						classNames.set(name, true);
						final symbol = classes.requireReflectionDescriptor(owner, core);
						classEntries.push("  {&" + symbol + ", " + nativeName(name) + "}");
						if (core != null)
							switch core.getKind() {
								case StringCore: stringSymbol = "&" + symbol;
								case ArrayCore: arraySymbol = "&" + symbol;
								case _:
							}
					case EnumValue:
						final name = facts.requirePublicReflectionName();
						if (enumNames.exists(name))
							throw "managed reflection repeats a public enum name: " + name;
						enumNames.set(name, true);
						enumEntries.push("  {&" + enums.requireSymbol(owner) + ", " + nativeName(name) + "}");
					case AbstractValue(_):
				}
			}
		if (requiresCoreClasses && (stringSymbol == "nullptr" || arraySymbol == "nullptr"))
			throw "managed getClass requires loaded String and Array core providers";
		classes.assertReflectionNames();
		return "inline const std::array<hxhx::managed::ClassReflectionEntry, "
			+ classEntries.length
			+ "> hxhx_reflection_classes{{\n"
			+ classEntries.join(",\n")
			+ "\n}};\n"
			+ "inline const std::array<hxhx::managed::EnumReflectionEntry, "
			+ enumEntries.length
			+ "> hxhx_reflection_enums{{\n"
			+ enumEntries.join(",\n")
			+ "\n}};\n"
			+ "inline const hxhx::managed::ClassDescriptor* hxhx_reflection_string = "
			+ stringSymbol
			+ ";\n"
			+ "inline const hxhx::managed::ClassDescriptor* hxhx_reflection_array = "
			+ arraySymbol
			+ ";\n";
	}

	/** Preserve every UTF-8 byte, including an embedded zero in a selected native name. */
	static function nativeName(name:String):String {
		return "std::string_view(" + CppManagedText.quotedBytes(name) + ", " + haxe.io.Bytes.ofString(name).length + ")";
	}
}
