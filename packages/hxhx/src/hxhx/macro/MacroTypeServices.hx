package hxhx.macro;

import TyAnonymousField.TyAnonymousFieldKind;
import haxe.macro.Expr;
import hxhxmacrohost.MacroContextWire;
import hxhxmacrohost.MacroSyntaxWire.MacroSyntaxWireReader;
import hxhxmacrohost.MacroSyntaxWire.MacroSyntaxWireWriter;

/**
	`Context.typeof`, `Context.follow`, and `Ref.get` for one macro call, bound to the real typer.

	- `typeof` imports the expression as parser syntax and types it at the call's module and class
	  (`TyperStage.typeStandaloneExpression`). A typing failure is an `error` at the expression's
	  position, which the plugin throws as `haxe.macro.Expr.Error`.
	- `follow` rebuilds the compiler's type from the plugin's (every ref is a handle) and follows it
	  as upstream's `follow` does (Haxe 4.3.7 `src/core/tFunctions.ml`, lines 493-519): monomorphs,
	  typedefs, and `Null<T>`; with `once`, one typedef step and no `Null`.
	- `refGet` answers the record of one handle. The format is `hxhxmacrohost.MacroTypeWire`'s.

	Facts the plugin receives and their gaps (see `EXPRESSION_MACRO_ARGUMENT_PLAN.md`, "Types in
	project macros"):
	- Shape, `toString`, pack, name, module, privacy, externs, type parameters, superclass,
	  interfaces, enum constructors, structure fields, and the implicit casts of an abstract.
	- A declaration's position is its source range when the parser recorded one; otherwise the
	  file's start. A method's position is where it is declared.
	- Metadata carries names only. Class fields list variables before methods. An abstract has no
	  operators, array access, or `impl`. A class has no constructor, `init`, or overrides.
	  A variable's position is its declaration's.
	- An optional function argument has type `Null<T>`, as upstream gives `?x:T`.
**/
class MacroTypeServices {
	final context:TyperContext;
	final loader:Null<ModuleLoader>;
	final index:TyperIndex;
	final callFile:String;

	public function new(context:TyperContext, loader:Null<ModuleLoader>, callFile:String) {
		this.context = context;
		this.loader = loader;
		this.index = context.getIndex();
		this.callFile = callFile;
	}

	public function typeof(expression:Expr):String {
		final positions = new MacroSyntaxPositions(callFile);
		final syntax = new MacroSyntaxImport(positions).result(expression);
		final anchor = positions.resolve(expression.pos);
		final type = try {
			TyperStage.typeStandaloneExpression(syntax, context, loader, anchor == null ? HxPos.unknown() : anchor);
		} catch (error:TyperError) {
			final message = TyperStage.extractRawDiagnostic(error.message);
			return MacroContextWire.respondError(MacroContextWire.ERROR, message == null ? error.message : message, expression.pos);
		}
		return respond(type);
	}

	public function follow(reader:MacroSyntaxWireReader):String {
		final type = importType(reader);
		final once = reader.bool();
		reader.finish();
		final followed = if (once) {
			final definition = type.getAliasDefinition();
			definition == null ? type : definition.instantiate(type.getTypeArguments());
		} else {
			TyAliasExpansion.revealNonNullable(type);
		};
		return respond(followed);
	}

	public function refGet(handle:Int):String {
		final entry = MacroTypeHandles.get(handle);
		final writer = MacroContextWire.response();
		try {
			record(writer, entry);
		} catch (error:MacroTypeUnsupported) {
			return MacroContextWire.respondError(MacroContextWire.UNSUPPORTED, error.message);
		}
		return writer.toString();
	}

	function respond(type:TyType):String {
		final writer = MacroContextWire.response();
		try {
			writeType(writer, type);
		} catch (error:MacroTypeUnsupported) {
			return MacroContextWire.respondError(MacroContextWire.UNSUPPORTED, error.message);
		}
		return writer.toString();
	}

	// Types to the plugin.

	function writeType(writer:MacroSyntaxWireWriter, type:TyType):Void {
		if (type.isNullable()) {
			writer.string("TAbstract");
			writeRef(writer, MacroTypeHandles.issue("abstract:Null", NullAbstract(index.getByFullName("Null"))), "Null");
			writer.count(1);
			writeType(writer, type.unwrapNull());
			return;
		}
		final alias = type.getAliasDefinition();
		if (alias != null) {
			writer.string("TType");
			writeRef(writer, MacroTypeHandles.issue("typedef:" + alias.getCanonicalName(), Alias(alias)), aliasLabel(alias));
			writeTypes(writer, type.getTypeArguments());
			return;
		}
		if (type.isDynamic()) {
			writer.string("TDynamic");
			final arguments = type.getTypeArguments();
			if (arguments.length == 1)
				writeType(writer, arguments[0]);
			else
				writer.absent();
			return;
		}
		if (type.isPrimitive()) {
			final name = type.getDisplay();
			writer.string(name == "String" ? "TInst" : "TAbstract");
			writeRef(writer, MacroTypeHandles.issue("primitive:" + name, Primitive(name, index.getByFullName(name))), name);
			writer.count(0);
			return;
		}
		final identity = type.getNominalIdentity();
		if (identity != null) {
			final info = index.getByFullName(identity.getCanonicalName());
			if (info == null)
				throw new MacroTypeUnsupported("the type `" + type.getDisplay() + "` has no declaration in this compilation");
			writer.string(Std.isOfType(info, TyAbstractInfo) ? "TAbstract" : info.getIsEnum() ? "TEnum" : "TInst");
			writeRef(writer, MacroTypeHandles.issue("nominal:" + info.getFullName(), Nominal(info)), nominalLabel(info));
			writeTypes(writer, type.getTypeArguments());
			return;
		}
		if (type.isFunction()) {
			writer.string("TFun");
			final parameters = type.getFunctionParameters();
			writer.count(parameters.length);
			for (parameter in parameters) {
				writer.string(parameter.name == null ? "" : parameter.name);
				writer.bool(parameter.isOptional);
				writeType(writer, parameter.isOptional && !parameter.type.isNullable() ? TyType.nullable(parameter.type) : parameter.type);
			}
			final result = type.getFunctionReturn();
			writeType(writer, result == null ? TyType.unknown() : result);
			return;
		}
		if (type.isAnonymous()) {
			writer.string("TAnonymous");
			writeRef(writer, MacroTypeHandles.issue(null, Anonymous(type)), "<anonymous>");
			return;
		}
		if (type.isTypeParameter()) {
			final parameter = type.getTypeParameterIdentity();
			writer.string("TInst");
			writeRef(writer, MacroTypeHandles.issue(null, TypeParameter(type)), parameter == null ? type.getDisplay() : parameter.getName());
			writer.count(0);
			return;
		}
		if (type.isUnknown() || type.isNullLiteral() || type.isOpenValue()) {
			writer.string("TMono");
			writeRef(writer, MacroTypeHandles.issue(null, Mono(type)), "<mono>");
			return;
		}
		throw new MacroTypeUnsupported("the type `" + type.getDisplay() + "` cannot be described to a macro in hxhx yet");
	}

	function writeTypes(writer:MacroSyntaxWireWriter, types:Array<TyType>):Void {
		writer.count(types.length);
		for (type in types)
			writeType(writer, type);
	}

	/** A ref: its handle and its `toString` text. (Not `ref`: reflaxe.ocaml would shadow OCaml's `ref`.) */
	static function writeRef(writer:MacroSyntaxWireWriter, handle:Int, label:String):Void {
		writer.int(handle);
		writer.string(label);
	}

	/** Upstream's `s_type_path`: the package and the type's own name, without its module. */
	static function nominalLabel(info:TyNominalInfo):String {
		final pack = packOf(info.getModulePath());
		return pack.length == 0 ? info.getShortName() : pack.join(".") + "." + info.getShortName();
	}

	static function aliasLabel(definition:TyAliasDefinition):String {
		final declaration = definition.getDeclaration();
		final packagePath = declaration.getContext().packagePath;
		return packagePath.length == 0 ? declaration.getShortName() : packagePath + "." + declaration.getShortName();
	}

	static function packOf(modulePath:String):Array<String> {
		final segments = modulePath.split(".");
		segments.pop();
		return segments;
	}

	// Records (`type.refGet`).

	function record(writer:MacroSyntaxWireWriter, entry:MacroTypeEntry):Void {
		switch entry {
			case Nominal(info):
				if (Std.isOfType(info, TyAbstractInfo))
					abstractRecord(writer, cast info)
				else if (info.getIsEnum())
					enumRecord(writer, info)
				else
					classRecord(writer, info);
			case Primitive(name, info):
				if (info != null)
					record(writer, Nominal(info))
				else
					primitiveRecord(writer, name);
			case NullAbstract(info):
				if (info != null)
					record(writer, Nominal(info))
				else
					primitiveRecord(writer, "Null");
			case Alias(definition):
				writer.string("typedef");
				final declaration = definition.getDeclaration();
				final resolution = declaration.getContext();
				writeBase(writer, resolution.packagePath.length == 0 ? [] : resolution.packagePath.split("."), declaration.getShortName(),
					declaration.getModulePath(), positionOf(resolution.filePath, resolution.position), declaration.getVisibility() == HxVisibility.Private,
					false, definition.getParameterIds(), []);
				writeType(writer, definition.getBody());
			case Anonymous(type):
				writer.string("anonymous");
				final fields = type.getAnonymousFields();
				writer.count(fields.length);
				for (field in fields)
					anonymousField(writer, field);
				writer.string("AClosed");
			case Mono(_):
				writer.string("mono");
				writer.absent();
			case TypeParameter(type):
				final parameter = type.getTypeParameterIdentity();
				writer.string("class");
				writeBase(writer, [], parameter == null ? type.getDisplay() : parameter.getName(), context.getModulePath(), unknownPosition(), false, false,
					[], []);
				writer.string("KTypeParameter");
				writer.count(0);
				writer.bool(false);
				writer.bool(false);
				writer.bool(false);
				writer.absent();
				writer.count(0);
				writeRef(writer, MacroTypeHandles.issue(null, Fields(null, false)), "class fields");
				writeRef(writer, MacroTypeHandles.issue(null, Fields(null, true)), "class fields");
			case Fields(info, statics):
				writer.string("fields");
				if (info == null)
					writer.count(0);
				else
					classFields(writer, info, statics);
		}
	}

	function classRecord(writer:MacroSyntaxWireWriter, info:TyNominalInfo):Void {
		final cls:Null<TyClassInfo> = Std.isOfType(info, TyClassInfo) ? cast info : null;
		writer.string("class");
		nominalBase(writer, info, cls == null ? [] : cls.getTypeParameterIds(), cls != null && cls.getIsExtern());
		writer.string("KNormal");
		writer.bool(cls != null && cls.getIsInterface());
		// hxhx's index does not record `final` or `abstract` classes yet.
		writer.bool(false);
		writer.bool(false);
		final superType = cls == null ? null : cls.getSuperType();
		if (superType == null)
			writer.absent();
		else
			classApplication(writer, superType);
		final interfaces = cls == null ? [] : cls.getInterfaceTypes();
		writer.count(interfaces.length);
		for (implemented in interfaces)
			classApplication(writer, implemented);
		writeRef(writer, MacroTypeHandles.issue("fields:" + info.getFullName(), Fields(info, false)), "class fields");
		writeRef(writer, MacroTypeHandles.issue("statics:" + info.getFullName(), Fields(info, true)), "class fields");
	}

	function classApplication(writer:MacroSyntaxWireWriter, type:TyType):Void {
		final identity = type.getNominalIdentity();
		final info = identity == null ? null : index.getByFullName(identity.getCanonicalName());
		if (info == null)
			throw new MacroTypeUnsupported("the class `" + type.getDisplay() + "` has no declaration in this compilation");
		writeRef(writer, MacroTypeHandles.issue("nominal:" + info.getFullName(), Nominal(info)), nominalLabel(info));
		writeTypes(writer, type.getTypeArguments());
	}

	function enumRecord(writer:MacroSyntaxWireWriter, info:TyNominalInfo):Void {
		writer.string("enum");
		final cls:Null<TyClassInfo> = Std.isOfType(info, TyClassInfo) ? cast info : null;
		nominalBase(writer, info, cls == null ? [] : cls.getTypeParameterIds(), cls != null && cls.getIsExtern());
		final declaration = info.getEnumDeclaration();
		final constructors = declaration == null ? [] : declaration.getConstructors();
		final enumValueType = TyType.nominal(info.getIdentity(), cls == null ? [] : [for (id in cls.getTypeParameterIds()) TyType.typeParameter(id)]);
		final position = declarationPosition(info);
		writer.count(constructors.length);
		for (ordinal in 0...constructors.length) {
			final constructor = constructors[ordinal];
			writer.string(constructor.name);
			final signature = constructor.arity == 0 ? null : info.staticMethod(constructor.name);
			if (signature == null) {
				writeType(writer, enumValueType);
			} else {
				writeType(writer, functionOf(signature, enumValueType));
			}
			writer.position(position);
			writer.int(ordinal);
			writer.optionalMetadata([]);
			writer.absent();
			writer.count(0);
		}
	}

	function abstractRecord(writer:MacroSyntaxWireWriter, info:TyAbstractInfo):Void {
		writer.string("abstract");
		nominalBase(writer, info, info.getTypeParameterIds(), false);
		writeType(writer, info.getUnderlyingType());
		writer.absent();
		final from = info.getImplicitFromTypes();
		writer.count(from.length);
		for (type in from)
			writeType(writer, type);
		final to = info.getImplicitToTypes();
		writer.count(to.length);
		for (type in to)
			writeType(writer, type);
	}

	/**
		A `StdTypes` type the index has no entry for (hxhx types them as primitives): a core-type
		abstract as `StdTypes.hx` declares it (`Int to Float`, `Null<T> from T to T`), or the
		`String` class.
	**/
	function primitiveRecord(writer:MacroSyntaxWireWriter, name:String):Void {
		final module = name == "String" ? "String" : "StdTypes";
		if (name == "String") {
			writer.string("class");
			writeBase(writer, [], name, module, unknownPosition(), false, true, [], []);
			writer.string("KNormal");
			writer.bool(false);
			writer.bool(false);
			writer.bool(false);
			writer.absent();
			writer.count(0);
			writeRef(writer, MacroTypeHandles.issue(null, Fields(null, false)), "class fields");
			writeRef(writer, MacroTypeHandles.issue(null, Fields(null, true)), "class fields");
			return;
		}
		writer.string("abstract");
		if (name == "Null") {
			final parameter = new TyTypeParameterId("abstract:Null", 0, "T");
			final value = TyType.typeParameter(parameter);
			writeBase(writer, [], name, module, unknownPosition(), false, false, [parameter], ["@:coreType"]);
			writeType(writer, value);
			writer.absent();
			writeTypes(writer, [value]);
			writeTypes(writer, [value]);
			return;
		}
		writeBase(writer, [], name, module, unknownPosition(), false, false, [], ["@:coreType"]);
		writeType(writer, TyType.fromHintText(name));
		writer.absent();
		writer.count(0);
		writeTypes(writer, name == "Int" ? [TyType.fromHintText("Float")] : []);
	}

	function nominalBase(writer:MacroSyntaxWireWriter, info:TyNominalInfo, parameters:Array<TyTypeParameterId>, isExtern:Bool):Void {
		final source = sourceClass(info);
		writeBase(writer, packOf(info.getModulePath()), info.getShortName(), info.getModulePath(), declarationPosition(info),
			info.getVisibility() == HxVisibility.Private, isExtern, parameters, source == null ? [] : HxClassDecl.getMetadata(source));
	}

	function writeBase(writer:MacroSyntaxWireWriter, pack:Array<String>, name:String, module:String, position:Position, isPrivate:Bool, isExtern:Bool,
			parameters:Array<TyTypeParameterId>, metadata:Array<String>):Void {
		writer.strings(pack);
		writer.string(name);
		writer.string(module);
		writer.position(position);
		writer.bool(isPrivate);
		writer.bool(isExtern);
		writer.count(parameters.length);
		for (parameter in parameters) {
			writer.string(parameter.getName());
			writeType(writer, TyType.typeParameter(parameter));
			writer.absent();
		}
		writer.optionalMetadata(metadataEntries(metadata, position));
		writer.absent();
	}

	/** Source metadata such as `@:coreType`; hxhx's own markers are left out. Names only. */
	static function metadataEntries(metadata:Array<String>, position:Position):Metadata {
		final out:Metadata = [];
		for (entry in metadata) {
			if (entry == null)
				continue;
			var text = StringTools.trim(entry);
			if (!StringTools.startsWith(text, "@"))
				continue;
			text = text.substr(1);
			final open = text.indexOf("(");
			final name = open < 0 ? text : text.substr(0, open);
			if (name.length > 0)
				out.push({name: name, params: [], pos: position});
		}
		return out;
	}

	function classFields(writer:MacroSyntaxWireWriter, info:TyNominalInfo, statics:Bool):Void {
		final position = declarationPosition(info);
		final variables = [for (field in info.getFieldInfos()) if (field.getIsStatic() == statics) field];
		final methods = [
			for (declaration in info.getDeclarations())
				if (declaration.getIsStatic() == statics
					&& declaration.getSignature().getName() != "new"
					&& !declaration.getIsEnumConstructor()) declaration
		];
		writer.count(variables.length + methods.length);
		for (field in variables) {
			writer.string(field.getName());
			writeType(writer, field.getType());
			writer.bool(field.getIsPublic());
			writer.bool(false);
			writer.bool(field.getIsFinal());
			writer.bool(false);
			writer.count(0);
			writer.optionalMetadata([]);
			writer.string("FVar");
			if (field.getIsInline()) {
				writer.string("AccInline");
				writer.string("AccNever");
			} else {
				access(writer, field.getPropertyGet(), false);
				access(writer, field.getPropertySet(), field.getIsFinal());
			}
			writer.position(position);
			writer.absent();
		}
		for (declaration in methods) {
			final signature = declaration.getSignature();
			final at = exportPosition(info, declaration.getPosition(), position);
			writer.string(signature.getName());
			writeType(writer, functionOf(signature, null));
			writer.bool(declaration.getIsPublic());
			writer.bool(declaration.getIsExtern());
			writer.bool(false);
			writer.bool(false);
			writer.count(0);
			writer.optionalMetadata(metadataEntries(declaration.getMetadata(), at));
			writer.string("FMethod");
			writer.string(declaration.getIsInline() ? "MethInline" : declaration.getIsDynamic() ? "MethDynamic" : "MethNormal");
			writer.position(at);
			writer.absent();
		}
	}

	static function access(writer:MacroSyntaxWireWriter, accessor:String, isFinal:Bool):Void {
		writer.string(switch accessor {
			case "null": "AccNo";
			case "never": "AccNever";
			case "get" | "set" | "dynamic": "AccCall";
			case _: isFinal ? "AccNever" : "AccNormal";
		});
	}

	function anonymousField(writer:MacroSyntaxWireWriter, field:TyAnonymousField):Void {
		writer.string(field.name);
		writeType(writer, field.isOptional && !field.type.isNullable() ? TyType.nullable(field.type) : field.type);
		writer.bool(field.visibility != HxVisibility.Private);
		writer.bool(false);
		final isFinal = switch field.kind {
			case Variable(finalField, _, _): finalField;
			case Method(_): false;
		};
		writer.bool(isFinal);
		writer.bool(false);
		writer.count(0);
		final position = positionOf(callFile, field.position);
		writer.optionalMetadata(metadataEntries(field.metadata, position));
		switch field.kind {
			case Variable(finalField, get, set):
				writer.string("FVar");
				access(writer, get, false);
				access(writer, set, finalField);
			case Method(_):
				writer.string("FMethod");
				writer.string("MethNormal");
		}
		writer.position(position);
		writer.absent();
	}

	static function functionOf(signature:TyFunSig, result:Null<TyType>):TyType {
		final names = signature.getArgNames();
		final types = signature.getArgs();
		final optional = signature.getArgOptional();
		final rest = signature.getArgRest();
		final parameters:Array<TyFunctionParameter> = [
			for (index in 0...types.length)
				{
					name: index < names.length ? names[index] : "",
					type: types[index],
					isOptional: index < optional.length && optional[index],
					isRest: index < rest.length && rest[index],
					metadata: []
				}
		];
		return TyType.functionSignature(parameters, result == null ? signature.getReturnType() : result);
	}

	// Positions.

	function sourceClass(info:TyNominalInfo):Null<HxClassDecl> {
		final module = index.getRegisteredModule(info.getModulePath());
		if (module == null)
			return null;
		for (candidate in HxModuleDecl.getClasses(ResolvedModule.getParsed(module).getDecl()))
			if (HxClassDecl.getName(candidate) == info.getShortName())
				return candidate;
		return null;
	}

	function declarationPosition(info:TyNominalInfo):Position {
		final module = index.getRegisteredModule(info.getModulePath());
		if (module == null)
			return unknownPosition();
		final file = ResolvedModule.getFilePath(module);
		final source = sourceClass(info);
		final range = source == null ? null : HxClassDecl.getSourceRange(source);
		final position:Position = range == null ? {file: file, min: 0, max: 0} : {file: file, min: range.start, max: range.end};
		return position;
	}

	function exportPosition(info:TyNominalInfo, position:Null<HxPos>, fallback:Position):Position {
		final module = index.getRegisteredModule(info.getModulePath());
		return module == null
			|| position == null
			|| !MacroSyntaxPositions.isKnown(position) ? fallback : positionOf(ResolvedModule.getFilePath(module), position);
	}

	static function positionOf(file:String, position:Null<HxPos>):Position {
		if (position == null || !MacroSyntaxPositions.isKnown(position)) {
			final start:Position = {file: file, min: 0, max: 0};
			return start;
		}
		return new MacroSyntaxPositions(file).export(position);
	}

	function unknownPosition():Position {
		final position:Position = {file: callFile, min: 0, max: 0};
		return position;
	}

	// Types from the plugin (`follow`).

	function importType(reader:MacroSyntaxWireReader):TyType {
		final tag = reader.string();
		return switch tag {
			case "TMono" | "TAnonymous":
				entryType(reader.int(), []);
			case "TEnum" | "TInst" | "TType" | "TAbstract":
				final handle = reader.int();
				final parameters = importTypes(reader);
				entryType(handle, parameters);
			case "TFun":
				final total = reader.count();
				final parameters:Array<TyFunctionParameter> = [];
				for (_ in 0...total) {
					final name = reader.string();
					final optional = reader.bool();
					final type = importType(reader);
					parameters.push({
						name: name,
						type: optional ? type.unwrapNull() : type,
						isOptional: optional,
						isRest: false,
						metadata: []
					});
				}
				TyType.functionSignature(parameters, importType(reader));
			case "TDynamic":
				if (!reader.absent())
					throw "a TDynamic with a type parameter cannot be sent back to hxhx yet";
				TyType.fromHintText("Dynamic");
			case other:
				throw "unknown type tag `" + other + "`";
		};
	}

	function importTypes(reader:MacroSyntaxWireReader):Array<TyType> {
		final total = reader.count();
		return [for (_ in 0...total) importType(reader)];
	}

	static function entryType(handle:Int, parameters:Array<TyType>):TyType {
		return switch MacroTypeHandles.get(handle) {
			case Nominal(info): TyType.nominal(info.getIdentity(), parameters);
			case Primitive(name, _): TyType.fromHintText(name);
			case NullAbstract(_):
				if (parameters.length != 1)
					throw "Null takes one type parameter";
				TyType.nullable(parameters[0]);
			case Alias(definition): TyType.aliasApplication(definition, parameters);
			case Anonymous(type) | Mono(type) | TypeParameter(type): type;
			case Fields(_, _): throw "type handle " + handle + " names class fields, not a type";
		};
	}
}
