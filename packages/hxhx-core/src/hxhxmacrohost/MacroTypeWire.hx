package hxhxmacrohost;

import haxe.macro.Expr;
import haxe.macro.Type;
import hxhxmacrohost.MacroSyntaxWire.MacroSyntaxWireReader;
import hxhxmacrohost.MacroSyntaxWire.MacroSyntaxWireWriter;

/**
	`haxe.macro.Type` values in a project-macro plugin, built from the compiler's answers.

	Why
	- `Context.typeof`, `Context.follow`, and `Ref.get` need the compiler's types. A plugin cannot
	  type code itself, so each is a `hxhx-macro-context.v1` request (`MacroContextWire`).
	- Upstream encodes types the same way (Haxe 4.3.7 `src/macro/macroApi.ml`, lines 1181-1245):
	  the shape of a type travels by value, and every `Ref` is a handle that the compiler reads
	  when the macro calls `get()`.

	What (the format; `hxhx.macro.MacroTypeExport` writes it on the compiler side)
	- A type is a tag and its payload:
	  `TMono` ref; `TEnum`, `TInst`, `TType`, `TAbstract` ref and parameters; `TFun` the arguments
	  (name, optional, type) and the result; `TAnonymous` ref; `TDynamic` an optional type.
	  `TLazy` never travels: the compiler forces lazy types first, as upstream does (line 1219).
	- A ref is the handle (`int`) and the text `toString()` returns.
	- `type.refGet` answers one record: `class`, `enum`, `typedef`, `abstract`, `anonymous`,
	  `mono` (an optional type), or `fields` (class fields). A record of a kind starts with the
	  base type facts: pack, name, module, position, private, extern, parameters, metadata, doc.
	- Handles are the compiler's (`hxhx.macro.MacroTypeHandles`): valid for the macro call that
	  received them. A stale or unknown handle is an `invalid` error.

	How
	- `typeof`, `follow`, and each `Ref.get` send one request through `call` (in a plugin,
	  `HxHxMacroModuleHost.call_host`). A compile error comes back as `haxe.macro.Expr.Error`,
	  which macro code may catch, as with upstream's typing errors.
	- Each `Ref` this decoder builds is remembered with its handle (`MacroTypeRefHandles`, one
	  typed store per kind, compared by identity), so `follow` can send a type the compiler gave
	  back. A `Ref` the macro built itself has no handle and is `invalid` there.
	- Every closure has an expression body that calls a method: the Stage3 emitter's block-bodied
	  closures cannot return a nullable value or a structure, and cannot loop over an array
	  (haxe_ocaml-kmm68).
	- Facts hxhx does not provide yet are absent or empty (see
	  `docs/00-project/EXPRESSION_MACRO_ARGUMENT_PLAN.md`, "Types in project macros"). Calls that
	  would change the compiler's state (`exclude`, `MetaAccess.add` and `remove`) and typed
	  expressions (`ClassField.expr`) fail as `unsupported`.
**/
class MacroTypeWire {
	final call:String->String;

	// The handles of the refs built here, one store for each kind of `Ref` a type can hold.
	final classRefs:MacroTypeRefHandles<ClassType> = new MacroTypeRefHandles<ClassType>();
	final enumRefs:MacroTypeRefHandles<EnumType> = new MacroTypeRefHandles<EnumType>();
	final defRefs:MacroTypeRefHandles<DefType> = new MacroTypeRefHandles<DefType>();
	final abstractRefs:MacroTypeRefHandles<AbstractType> = new MacroTypeRefHandles<AbstractType>();
	final anonRefs:MacroTypeRefHandles<AnonType> = new MacroTypeRefHandles<AnonType>();
	final monoRefs:MacroTypeRefHandles<Null<Type>> = new MacroTypeRefHandles<Null<Type>>();

	public function new(call:String->String) {
		this.call = call;
	}

	/** The type of `e` at the macro call (`Context.typeof`). */
	public function typeof(e:Expr):Type {
		final writer = MacroContextWire.request(MacroContextWire.TYPEOF);
		writer.expr(e);
		return answer(writer.toString());
	}

	/** `t` without its typedefs, monomorphs, and `Null` (`Context.follow`); one step when `once`. */
	public function follow(t:Type, once:Bool):Type {
		final writer = MacroContextWire.request(MacroContextWire.FOLLOW);
		type(writer, t);
		writer.bool(once);
		return answer(writer.toString());
	}

	function answer(request:String):Type {
		final reader = response(request);
		final result = readType(reader);
		reader.finish();
		return result;
	}

	/** The reader of the compiler's answer; a compile error is thrown as `haxe.macro.Expr.Error`. */
	function response(request:String):MacroSyntaxWireReader {
		final payload = call(request);
		final failure = MacroContextWire.failureOf(payload);
		if (failure.failed && failure.kind == MacroContextWire.ERROR && failure.position != null)
			throw new haxe.macro.Expr.Error(failure.message, failure.position);
		return MacroContextWire.value(payload);
	}

	function record(handle:Int, kind:String):MacroSyntaxWireReader {
		final writer = MacroContextWire.request(MacroContextWire.REF_GET);
		writer.int(handle);
		final reader = response(writer.toString());
		final found = reader.string();
		if (found != kind)
			throw "macro context: invalid: type handle " + handle + " is a `" + found + "`, not a `" + kind + "`";
		return reader;
	}

	// Types from the compiler.

	public function readType(reader:MacroSyntaxWireReader):Type {
		final name = reader.string();
		return switch name {
			case "TMono":
				final ref = monoRef(reader);
				TMono(ref);
			case "TEnum":
				final ref = enumRef(reader);
				final params = readTypes(reader);
				TEnum(ref, params);
			case "TInst":
				final ref = classRef(reader);
				final params = readTypes(reader);
				TInst(ref, params);
			case "TType":
				final ref = defRef(reader);
				final params = readTypes(reader);
				TType(ref, params);
			case "TFun":
				final total = reader.count();
				final args:Array<{name:String, opt:Bool, t:Type}> = [];
				for (_ in 0...total) {
					final argName = reader.string();
					final opt = reader.bool();
					final argType = readType(reader);
					final arg:{name:String, opt:Bool, t:Type} = {name: argName, opt: opt, t: argType};
					args.push(arg);
				}
				final ret = readType(reader);
				TFun(args, ret);
			case "TAnonymous":
				final ref = anonRef(reader);
				TAnonymous(ref);
			case "TDynamic":
				final inner:Null<Type> = reader.absent() ? null : readType(reader);
				TDynamic(inner);
			case "TAbstract":
				final ref = abstractRef(reader);
				final params = readTypes(reader);
				TAbstract(ref, params);
			case _:
				throw "macro context: invalid: unknown type tag `" + name + "`";
		};
	}

	function readTypes(reader:MacroSyntaxWireReader):Array<Type> {
		final total = reader.count();
		final out:Array<Type> = [];
		for (_ in 0...total)
			out.push(readType(reader));
		return out;
	}

	// Refs: `get` asks the compiler each time, as upstream's refs do.

	function classRef(reader:MacroSyntaxWireReader):Ref<ClassType> {
		final handle = reader.int();
		final label = reader.string();
		final ref:Ref<ClassType> = {get: () -> classType(record(handle, "class")), toString: () -> label};
		classRefs.remember(ref, handle);
		return ref;
	}

	function enumRef(reader:MacroSyntaxWireReader):Ref<EnumType> {
		final handle = reader.int();
		final label = reader.string();
		final ref:Ref<EnumType> = {get: () -> enumType(record(handle, "enum")), toString: () -> label};
		enumRefs.remember(ref, handle);
		return ref;
	}

	function defRef(reader:MacroSyntaxWireReader):Ref<DefType> {
		final handle = reader.int();
		final label = reader.string();
		final ref:Ref<DefType> = {get: () -> defType(record(handle, "typedef")), toString: () -> label};
		defRefs.remember(ref, handle);
		return ref;
	}

	function abstractRef(reader:MacroSyntaxWireReader):Ref<AbstractType> {
		final handle = reader.int();
		final label = reader.string();
		final ref:Ref<AbstractType> = {get: () -> abstractType(record(handle, "abstract")), toString: () -> label};
		abstractRefs.remember(ref, handle);
		return ref;
	}

	function anonRef(reader:MacroSyntaxWireReader):Ref<AnonType> {
		final handle = reader.int();
		final label = reader.string();
		final ref:Ref<AnonType> = {get: () -> anonType(record(handle, "anonymous")), toString: () -> label};
		anonRefs.remember(ref, handle);
		return ref;
	}

	function monoRef(reader:MacroSyntaxWireReader):Ref<Null<Type>> {
		final handle = reader.int();
		final label = reader.string();
		// A bound method, not a closure: the emitter's closures cannot return a nullable value.
		final binding = new MacroTypeMonoRef(monoBinding, handle);
		final ref:Ref<Null<Type>> = {get: binding.get, toString: () -> label};
		monoRefs.remember(ref, handle);
		return ref;
	}

	function fieldsRef(reader:MacroSyntaxWireReader):Ref<Array<ClassField>> {
		final handle = reader.int();
		final label = reader.string();
		final ref:Ref<Array<ClassField>> = {get: () -> fieldList(handle), toString: () -> label};
		return ref;
	}

	function monoBinding(handle:Int):Null<Type> {
		final found = record(handle, "mono");
		final bound:Null<Type> = found.absent() ? null : readType(found);
		found.finish();
		return bound;
	}

	function fieldList(handle:Int):Array<ClassField> {
		final found = record(handle, "fields");
		final fields = classFields(found);
		found.finish();
		return fields;
	}

	/** A ref whose value travelled with its owner, such as a field's empty overload list. */
	static function localFields(value:Array<ClassField>, label:String):Ref<Array<ClassField>> {
		final ref:Ref<Array<ClassField>> = {get: () -> value, toString: () -> label};
		return ref;
	}

	// Records.

	function classType(reader:MacroSyntaxWireReader):ClassType {
		final base = baseType(reader);
		final kind = classKind(reader);
		final isInterface = reader.bool();
		final isFinal = reader.bool();
		final isAbstract = reader.bool();
		final superClass:Null<{t:Ref<ClassType>, params:Array<Type>}> = reader.absent() ? null : classApplication(reader);
		final interfaceTotal = reader.count();
		final interfaces:Array<{t:Ref<ClassType>, params:Array<Type>}> = [];
		for (_ in 0...interfaceTotal)
			interfaces.push(classApplication(reader));
		final fields = fieldsRef(reader);
		final statics = fieldsRef(reader);
		final constructor:Null<Ref<ClassField>> = null;
		final overrides:Array<Ref<ClassField>> = [];
		reader.finish();
		final value:ClassType = {
			pack: base.pack,
			name: base.name,
			module: base.module,
			pos: base.pos,
			isPrivate: base.isPrivate,
			isExtern: base.isExtern,
			params: base.params,
			meta: base.meta,
			doc: base.doc,
			exclude: base.exclude,
			kind: kind,
			isInterface: isInterface,
			isFinal: isFinal,
			isAbstract: isAbstract,
			superClass: superClass,
			interfaces: interfaces,
			fields: fields,
			statics: statics,
			constructor: constructor,
			init: null,
			overrides: overrides
		};
		return value;
	}

	function classApplication(reader:MacroSyntaxWireReader):{t:Ref<ClassType>, params:Array<Type>} {
		final ref = classRef(reader);
		final params = readTypes(reader);
		final value:{t:Ref<ClassType>, params:Array<Type>} = {t: ref, params: params};
		return value;
	}

	function classKind(reader:MacroSyntaxWireReader):ClassKind {
		final name = reader.string();
		return switch name {
			case "KNormal": KNormal;
			case "KTypeParameter":
				final constraints = readTypes(reader);
				KTypeParameter(constraints);
			case "KModuleFields":
				final module = reader.string();
				KModuleFields(module);
			case "KGeneric": KGeneric;
			case "KMacroType": KMacroType;
			case "KGenericBuild": KGenericBuild;
			case _: throw "macro context: invalid: unknown class kind `" + name + "`";
		};
	}

	function enumType(reader:MacroSyntaxWireReader):EnumType {
		final base = baseType(reader);
		final total = reader.count();
		final names:Array<String> = [];
		// `new StringMap()`, not `new Map()`: the Stage3 emitter builds `new Map()` through the
		// abstract's `toStringMap` as a different object than its native map methods expect.
		final table = new haxe.ds.StringMap<EnumField>();
		for (_ in 0...total) {
			final field = enumField(reader);
			names.push(field.name);
			table.set(field.name, field);
		}
		final constructs:Map<String, EnumField> = table;
		reader.finish();
		final value:EnumType = {
			pack: base.pack,
			name: base.name,
			module: base.module,
			pos: base.pos,
			isPrivate: base.isPrivate,
			isExtern: base.isExtern,
			params: base.params,
			meta: base.meta,
			doc: base.doc,
			exclude: base.exclude,
			constructs: constructs,
			names: names
		};
		return value;
	}

	function enumField(reader:MacroSyntaxWireReader):EnumField {
		final name = reader.string();
		final fieldType = readType(reader);
		final pos = reader.position();
		final index = reader.int();
		final meta = metaAccess(reader);
		final doc = reader.optionalString();
		final params = typeParameters(reader);
		final value:EnumField = {
			name: name,
			type: fieldType,
			pos: pos,
			meta: meta,
			index: index,
			doc: doc,
			params: params
		};
		return value;
	}

	function defType(reader:MacroSyntaxWireReader):DefType {
		final base = baseType(reader);
		final target = readType(reader);
		reader.finish();
		final value:DefType = {
			pack: base.pack,
			name: base.name,
			module: base.module,
			pos: base.pos,
			isPrivate: base.isPrivate,
			isExtern: base.isExtern,
			params: base.params,
			meta: base.meta,
			doc: base.doc,
			exclude: base.exclude,
			type: target
		};
		return value;
	}

	function abstractType(reader:MacroSyntaxWireReader):AbstractType {
		final base = baseType(reader);
		final underlying = readType(reader);
		final impl:Null<Ref<ClassType>> = reader.absent() ? null : classRef(reader);
		final from = casts(reader);
		final to = casts(reader);
		reader.finish();
		final binops:Array<{op:Binop, field:ClassField}> = [];
		final unops:Array<{op:Unop, postFix:Bool, field:ClassField}> = [];
		final array:Array<ClassField> = [];
		final value:AbstractType = {
			pack: base.pack,
			name: base.name,
			module: base.module,
			pos: base.pos,
			isPrivate: base.isPrivate,
			isExtern: base.isExtern,
			params: base.params,
			meta: base.meta,
			doc: base.doc,
			exclude: base.exclude,
			type: underlying,
			impl: impl,
			binops: binops,
			unops: unops,
			from: from,
			to: to,
			array: array,
			resolve: null,
			resolveWrite: null
		};
		return value;
	}

	/** Implicit casts; hxhx sends only their types, so `field` is null. */
	function casts(reader:MacroSyntaxWireReader):Array<{t:Type, field:Null<ClassField>}> {
		final total = reader.count();
		final out:Array<{t:Type, field:Null<ClassField>}> = [];
		for (_ in 0...total) {
			final castType = readType(reader);
			final entry:{t:Type, field:Null<ClassField>} = {t: castType, field: null};
			out.push(entry);
		}
		return out;
	}

	function anonType(reader:MacroSyntaxWireReader):AnonType {
		final fields = classFields(reader);
		final statusName = reader.string();
		final status:AnonStatus = switch statusName {
			case "AClosed": AClosed;
			case "AOpened": AOpened;
			case "AConst": AConst;
			case _: throw "macro context: invalid: unknown structure status `" + statusName + "`";
		};
		reader.finish();
		final value:AnonType = {fields: fields, status: status};
		return value;
	}

	function classFields(reader:MacroSyntaxWireReader):Array<ClassField> {
		final total = reader.count();
		final out:Array<ClassField> = [];
		for (_ in 0...total)
			out.push(classField(reader));
		return out;
	}

	function classField(reader:MacroSyntaxWireReader):ClassField {
		final name = reader.string();
		final fieldType = readType(reader);
		final isPublic = reader.bool();
		final isExtern = reader.bool();
		final isFinal = reader.bool();
		final isAbstract = reader.bool();
		final params = typeParameters(reader);
		final meta = metaAccess(reader);
		final kind = fieldKind(reader);
		final pos = reader.position();
		final doc = reader.optionalString();
		final value:ClassField = {
			name: name,
			type: fieldType,
			isPublic: isPublic,
			isExtern: isExtern,
			isFinal: isFinal,
			isAbstract: isAbstract,
			params: params,
			meta: meta,
			kind: kind,
			expr: MacroTypeUnavailable.typedExpression,
			pos: pos,
			doc: doc,
			overloads: localFields([], "overloads")
		};
		return value;
	}

	function fieldKind(reader:MacroSyntaxWireReader):FieldKind {
		final name = reader.string();
		return switch name {
			case "FVar":
				final read = varAccess(reader);
				final write = varAccess(reader);
				FVar(read, write);
			case "FMethod":
				final kind = methodKind(reader);
				FMethod(kind);
			case _: throw "macro context: invalid: unknown field kind `" + name + "`";
		};
	}

	function varAccess(reader:MacroSyntaxWireReader):VarAccess {
		final name = reader.string();
		return switch name {
			case "AccNormal": AccNormal;
			case "AccNo": AccNo;
			case "AccNever": AccNever;
			case "AccCall": AccCall;
			case "AccInline": AccInline;
			case "AccCtor": AccCtor;
			case "AccRequire":
				final required = reader.string();
				final message = reader.optionalString();
				AccRequire(required, message);
			case _: throw "macro context: invalid: unknown variable access `" + name + "`";
		};
	}

	function methodKind(reader:MacroSyntaxWireReader):MethodKind {
		final name = reader.string();
		return switch name {
			case "MethNormal": MethNormal;
			case "MethInline": MethInline;
			case "MethDynamic": MethDynamic;
			case "MethMacro": MethMacro;
			case _: throw "macro context: invalid: unknown method kind `" + name + "`";
		};
	}

	function baseType(reader:MacroSyntaxWireReader):BaseType {
		final pack = readStrings(reader);
		final name = reader.string();
		final module = reader.string();
		final pos = reader.position();
		final isPrivate = reader.bool();
		final isExtern = reader.bool();
		final params = typeParameters(reader);
		final meta = metaAccess(reader);
		final doc = reader.optionalString();
		final value:BaseType = {
			pack: pack,
			name: name,
			module: module,
			pos: pos,
			isPrivate: isPrivate,
			isExtern: isExtern,
			params: params,
			meta: meta,
			doc: doc,
			exclude: () -> throw "macro context: unsupported: excluding a type (BaseType.exclude) is not available in hxhx yet"
		};
		return value;
	}

	function readStrings(reader:MacroSyntaxWireReader):Array<String> {
		final total = reader.count();
		final out:Array<String> = [];
		for (_ in 0...total)
			out.push(reader.string());
		return out;
	}

	function typeParameters(reader:MacroSyntaxWireReader):Array<TypeParameter> {
		final total = reader.count();
		final out:Array<TypeParameter> = [];
		for (_ in 0...total) {
			final name = reader.string();
			final parameterType = readType(reader);
			final defaultType:Null<Type> = reader.absent() ? null : readType(reader);
			final parameter:TypeParameter = {name: name, t: parameterType, defaultType: defaultType};
			out.push(parameter);
		}
		return out;
	}

	/** Metadata as the compiler sent it; reading is local, changing it is `unsupported`. */
	function metaAccess(reader:MacroSyntaxWireReader):MetaAccess {
		final read = reader.optionalMetadata();
		final entries:Metadata = read == null ? [] : read;
		final access:MetaAccess = {
			get: () -> entries.copy(),
			extract: name -> metadataNamed(entries, name),
			add: (name, params, pos) -> throw "macro context: unsupported: changing type metadata (MetaAccess.add) is not available in hxhx yet",
			remove: name -> throw "macro context: unsupported: changing type metadata (MetaAccess.remove) is not available in hxhx yet",
			has: name -> metadataNamed(entries, name).length > 0
		};
		return access;
	}

	static function metadataNamed(entries:Metadata, name:String):Array<MetadataEntry> {
		final out:Array<MetadataEntry> = [];
		for (entry in entries)
			if (entry.name == name)
				out.push(entry);
		return out;
	}

	// Types sent back (`follow`).

	public function type(writer:MacroSyntaxWireWriter, t:Type):Void {
		switch t {
			case TMono(ref):
				writer.string("TMono");
				writer.int(monoRefs.handleOf(ref));
			case TEnum(ref, params):
				writer.string("TEnum");
				writer.int(enumRefs.handleOf(ref));
				types(writer, params);
			case TInst(ref, params):
				writer.string("TInst");
				writer.int(classRefs.handleOf(ref));
				types(writer, params);
			case TType(ref, params):
				writer.string("TType");
				writer.int(defRefs.handleOf(ref));
				types(writer, params);
			case TFun(args, ret):
				writer.string("TFun");
				writer.count(args.length);
				for (arg in args) {
					writer.string(arg.name);
					writer.bool(arg.opt);
					type(writer, arg.t);
				}
				type(writer, ret);
			case TAnonymous(ref):
				writer.string("TAnonymous");
				writer.int(anonRefs.handleOf(ref));
			case TDynamic(inner):
				writer.string("TDynamic");
				if (inner == null)
					writer.absent();
				else
					type(writer, inner);
			case TAbstract(ref, params):
				writer.string("TAbstract");
				writer.int(abstractRefs.handleOf(ref));
				types(writer, params);
			case TLazy(_):
				throw "macro context: invalid: a TLazy type cannot be sent to the compiler";
		}
	}

	function types(writer:MacroSyntaxWireWriter, values:Array<Type>):Void {
		writer.count(values.length);
		for (value in values)
			type(writer, value);
	}
}
