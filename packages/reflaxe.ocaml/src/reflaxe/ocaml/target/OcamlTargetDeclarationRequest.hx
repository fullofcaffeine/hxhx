package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

typedef OcamlTargetArgumentInput = {
	final name:String;
	final typeIdentity:String;
	final typeDisplay:String;
	final isOptional:Bool;
	final isRest:Bool;
};

typedef OcamlTargetFieldInput = {
	final canonicalIdentity:String;
	final name:String;
	final typeIdentity:String;
	final typeDisplay:String;
	final isStatic:Bool;
	final isPublic:Bool;
	final isFinal:Bool;
	final isInline:Bool;
	final hasInitializer:Bool;
	final propertyGet:String;
	final propertySet:String;
	final noImportGlobal:Bool;
};

typedef OcamlTargetMethodInput = {
	final canonicalIdentity:String;
	final name:String;
	final typeParameters:Array<String>;
	final arguments:Array<OcamlTargetArgumentInput>;
	final returnTypeIdentity:String;
	final returnTypeDisplay:String;
	final isStatic:Bool;
	final isPublic:Bool;
	final isInline:Bool;
	final isDynamic:Bool;
	final hasBody:Bool;
	final isEnumConstructor:Bool;
	final noImportGlobal:Bool;
};

typedef OcamlTargetClassInput = {
	final canonicalIdentity:String;
	final moduleIdentity:String;
	final typeParameters:Array<String>;
	final ?superClassIdentity:String;
	final ?superTypeIdentity:String;
	final ?superTypeDisplay:String;
	final fields:Array<OcamlTargetFieldInput>;
	final methods:Array<OcamlTargetMethodInput>;
};

/**
	A copied argument signature that does not retain a host compiler object.

	The standalone Haxe compiler and native `hxhx` build these values independently.
	The target can therefore compare or consume the same facts without fabricating
	macro reflection objects in the native host.
**/
class OcamlTargetArgumentFact {
	public final name:String;
	public final typeIdentity:String;
	public final typeDisplay:String;
	public final isOptional:Bool;
	public final isRest:Bool;

	public function new(input:OcamlTargetArgumentInput) {
		name = required(input.name, "argument name");
		typeIdentity = required(input.typeIdentity, "argument type identity");
		typeDisplay = required(input.typeDisplay, "argument type display");
		isOptional = input.isOptional;
		isRest = input.isRest;
	}

	public function addIdentity(out:Array<Null<String>>):Void {
		out.push(name);
		out.push(typeIdentity);
		out.push(typeDisplay);
		out.push(flag(isOptional));
		out.push(flag(isRest));
	}

	static function required(value:String, label:String):String
		return OcamlTargetDeclarationRequest.required(value, label);

	static function flag(value:Bool):String
		return value ? "1" : "0";
}

/** An immutable field declaration supplied to the standalone OCaml target. **/
class OcamlTargetFieldFact {
	public final canonicalIdentity:String;
	public final name:String;
	public final typeIdentity:String;
	public final typeDisplay:String;
	public final isStatic:Bool;
	public final isPublic:Bool;
	public final isFinal:Bool;
	public final isInline:Bool;
	public final hasInitializer:Bool;
	public final propertyGet:String;
	public final propertySet:String;
	public final noImportGlobal:Bool;

	public function new(input:OcamlTargetFieldInput) {
		canonicalIdentity = OcamlTargetDeclarationRequest.required(input.canonicalIdentity, "field identity");
		name = OcamlTargetDeclarationRequest.required(input.name, "field name");
		typeIdentity = OcamlTargetDeclarationRequest.required(input.typeIdentity, "field type identity");
		typeDisplay = OcamlTargetDeclarationRequest.required(input.typeDisplay, "field type display");
		isStatic = input.isStatic;
		isPublic = input.isPublic;
		isFinal = input.isFinal;
		isInline = input.isInline;
		hasInitializer = input.hasInitializer;
		propertyGet = input.propertyGet == null ? "" : input.propertyGet;
		propertySet = input.propertySet == null ? "" : input.propertySet;
		noImportGlobal = input.noImportGlobal;
	}

	public function addIdentity(out:Array<Null<String>>):Void {
		out.push(canonicalIdentity);
		out.push(name);
		out.push(typeIdentity);
		out.push(typeDisplay);
		out.push(OcamlTargetDeclarationRequest.flag(isStatic));
		out.push(OcamlTargetDeclarationRequest.flag(isPublic));
		out.push(OcamlTargetDeclarationRequest.flag(isFinal));
		out.push(OcamlTargetDeclarationRequest.flag(isInline));
		out.push(OcamlTargetDeclarationRequest.flag(hasInitializer));
		out.push(propertyGet);
		out.push(propertySet);
		out.push(OcamlTargetDeclarationRequest.flag(noImportGlobal));
	}
}

/** An immutable method declaration supplied to the standalone OCaml target. **/
class OcamlTargetMethodFact {
	public final canonicalIdentity:String;
	public final name:String;

	final typeParameters:Array<String>;
	final arguments:Array<OcamlTargetArgumentFact>;

	public final returnTypeIdentity:String;
	public final returnTypeDisplay:String;
	public final isStatic:Bool;
	public final isPublic:Bool;
	public final isInline:Bool;
	public final isDynamic:Bool;
	public final hasBody:Bool;
	public final isEnumConstructor:Bool;
	public final noImportGlobal:Bool;

	public function new(input:OcamlTargetMethodInput) {
		canonicalIdentity = OcamlTargetDeclarationRequest.required(input.canonicalIdentity, "method identity");
		name = OcamlTargetDeclarationRequest.required(input.name, "method name");
		typeParameters = copyRequired(input.typeParameters, "method type parameter");
		arguments = input.arguments == null ? [] : [for (argument in input.arguments) new OcamlTargetArgumentFact(argument)];
		returnTypeIdentity = OcamlTargetDeclarationRequest.required(input.returnTypeIdentity, "method return type identity");
		returnTypeDisplay = OcamlTargetDeclarationRequest.required(input.returnTypeDisplay, "method return type display");
		isStatic = input.isStatic;
		isPublic = input.isPublic;
		isInline = input.isInline;
		isDynamic = input.isDynamic;
		hasBody = input.hasBody;
		isEnumConstructor = input.isEnumConstructor;
		noImportGlobal = input.noImportGlobal;
	}

	public function copyTypeParameters():Array<String>
		return typeParameters.copy();

	public function copyArguments():Array<OcamlTargetArgumentFact>
		return arguments.copy();

	public function addIdentity(out:Array<Null<String>>):Void {
		out.push(canonicalIdentity);
		out.push(name);
		OcamlTargetDeclarationRequest.addStrings(out, typeParameters);
		out.push(returnTypeIdentity);
		out.push(returnTypeDisplay);
		out.push(OcamlTargetDeclarationRequest.flag(isStatic));
		out.push(OcamlTargetDeclarationRequest.flag(isPublic));
		out.push(OcamlTargetDeclarationRequest.flag(isInline));
		out.push(OcamlTargetDeclarationRequest.flag(isDynamic));
		out.push(OcamlTargetDeclarationRequest.flag(hasBody));
		out.push(OcamlTargetDeclarationRequest.flag(isEnumConstructor));
		out.push(OcamlTargetDeclarationRequest.flag(noImportGlobal));
		out.push(Std.string(arguments.length));
		for (argument in arguments)
			argument.addIdentity(out);
	}

	static function copyRequired(values:Array<String>, label:String):Array<String> {
		if (values == null)
			return [];
		return [for (value in values) OcamlTargetDeclarationRequest.required(value, label)];
	}
}

/** An immutable class declaration supplied to the standalone OCaml target. **/
class OcamlTargetClassFact {
	public final canonicalIdentity:String;
	public final moduleIdentity:String;

	final typeParameters:Array<String>;

	public final superClassIdentity:Null<String>;
	public final superTypeIdentity:Null<String>;
	public final superTypeDisplay:Null<String>;

	final fields:Array<OcamlTargetFieldFact>;
	final methods:Array<OcamlTargetMethodFact>;

	public function new(input:OcamlTargetClassInput) {
		canonicalIdentity = OcamlTargetDeclarationRequest.required(input.canonicalIdentity, "class identity");
		moduleIdentity = OcamlTargetDeclarationRequest.required(input.moduleIdentity, "module identity");
		typeParameters = input.typeParameters == null ? [] : [
			for (value in input.typeParameters)
				OcamlTargetDeclarationRequest.required(value, "class type parameter")
		];
		final hasAnySuperFact = input.superClassIdentity != null || input.superTypeIdentity != null || input.superTypeDisplay != null;
		final hasEverySuperFact = input.superClassIdentity != null && input.superTypeIdentity != null && input.superTypeDisplay != null;
		if (hasAnySuperFact != hasEverySuperFact)
			throw "OCaml target declaration request requires all superclass facts or none";
		superClassIdentity = input.superClassIdentity;
		superTypeIdentity = input.superTypeIdentity;
		superTypeDisplay = input.superTypeDisplay;
		final copiedFields = input.fields == null ? [] : [for (field in input.fields) new OcamlTargetFieldFact(field)];
		final copiedMethods = input.methods == null ? [] : [for (method in input.methods) new OcamlTargetMethodFact(method)];
		copiedFields.sort((left, right) -> Reflect.compare(left.canonicalIdentity, right.canonicalIdentity));
		copiedMethods.sort((left, right) -> Reflect.compare(left.canonicalIdentity, right.canonicalIdentity));
		fields = uniqueFields(copiedFields);
		methods = uniqueMethods(copiedMethods);
	}

	public function copyTypeParameters():Array<String>
		return typeParameters.copy();

	public function copyFields():Array<OcamlTargetFieldFact>
		return fields.copy();

	public function copyMethods():Array<OcamlTargetMethodFact>
		return methods.copy();

	public function addIdentity(out:Array<Null<String>>):Void {
		out.push(canonicalIdentity);
		out.push(moduleIdentity);
		OcamlTargetDeclarationRequest.addStrings(out, typeParameters);
		out.push(superClassIdentity);
		out.push(superTypeIdentity);
		out.push(superTypeDisplay);
		out.push(Std.string(fields.length));
		for (field in fields)
			field.addIdentity(out);
		out.push(Std.string(methods.length));
		for (method in methods)
			method.addIdentity(out);
	}

	function uniqueFields(values:Array<OcamlTargetFieldFact>):Array<OcamlTargetFieldFact> {
		final result = new Array<OcamlTargetFieldFact>();
		for (value in values) {
			final previous = result.length == 0 ? null : result[result.length - 1];
			if (previous == null || previous.canonicalIdentity != value.canonicalIdentity) {
				result.push(value);
			} else if (fieldFingerprint(previous) != fieldFingerprint(value)) {
				throw 'OCaml target declaration request contains conflicting field ${value.canonicalIdentity} in ${canonicalIdentity}';
			}
		}
		return result;
	}

	function uniqueMethods(values:Array<OcamlTargetMethodFact>):Array<OcamlTargetMethodFact> {
		final result = new Array<OcamlTargetMethodFact>();
		for (value in values) {
			final previous = result.length == 0 ? null : result[result.length - 1];
			if (previous == null || previous.canonicalIdentity != value.canonicalIdentity) {
				result.push(value);
			} else if (methodFingerprint(previous) != methodFingerprint(value)) {
				throw 'OCaml target declaration request contains conflicting method ${value.canonicalIdentity} in ${canonicalIdentity}';
			}
		}
		return result;
	}

	static function fieldFingerprint(value:OcamlTargetFieldFact):String {
		final facts = new Array<Null<String>>();
		value.addIdentity(facts);
		return OcamlTargetDeclarationRequest.encode(facts);
	}

	static function methodFingerprint(value:OcamlTargetMethodFact):String {
		final facts = new Array<Null<String>>();
		value.addIdentity(facts);
		return OcamlTargetDeclarationRequest.encode(facts);
	}
}

/**
	The first host-independent input contract for the standalone OCaml target.

	This revision covers declaration and signature facts only. It intentionally does
	not claim to carry typed expression bodies. `hostProgramRevision` is diagnostic
	provenance and is excluded from the semantic identity, which lets two independent
	host adapters prove that they supplied equivalent target facts.
**/
class OcamlTargetDeclarationRequest {
	public static final SCHEMA_REVISION = "reflaxe-ocaml-target-declarations-v1";

	public final hostProgramRevision:String;

	final classes:Array<OcamlTargetClassFact>;
	final canonicalIdentity:String;

	public function new(hostProgramRevision:String, inputs:Array<OcamlTargetClassInput>) {
		this.hostProgramRevision = required(hostProgramRevision, "host program revision");
		final copiedClasses = inputs == null ? [] : [for (input in inputs) new OcamlTargetClassFact(input)];
		copiedClasses.sort((left, right) -> Reflect.compare(left.canonicalIdentity, right.canonicalIdentity));
		classes = uniqueClasses(copiedClasses);
		final identityFacts = new Array<Null<String>>();
		identityFacts.push(SCHEMA_REVISION);
		identityFacts.push(Std.string(classes.length));
		for (classFact in classes)
			classFact.addIdentity(identityFacts);
		canonicalIdentity = Sha256.encode(encode(identityFacts));
	}

	/** Return the semantic identity shared by equivalent stock and native inputs. **/
	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function copyClasses():Array<OcamlTargetClassFact>
		return classes.copy();

	/** Distinguish same-named secondary or private types owned by different modules. **/
	public static function classIdentity(moduleIdentity:String, typeIdentity:String):String {
		final moduleName = required(moduleIdentity, "class module identity");
		final typeName = required(typeIdentity, "class type identity");
		return moduleName == typeName ? typeName : moduleName + "#" + typeName;
	}

	function uniqueClasses(values:Array<OcamlTargetClassFact>):Array<OcamlTargetClassFact> {
		final result = new Array<OcamlTargetClassFact>();
		for (value in values) {
			final previous = result.length == 0 ? null : result[result.length - 1];
			if (previous == null || previous.canonicalIdentity != value.canonicalIdentity) {
				result.push(value);
			} else if (classFingerprint(previous) != classFingerprint(value)) {
				throw 'OCaml target declaration request contains conflicting class ${value.canonicalIdentity} in program';
			}
		}
		return result;
	}

	static function classFingerprint(value:OcamlTargetClassFact):String {
		final facts = new Array<Null<String>>();
		value.addIdentity(facts);
		return encode(facts);
	}

	/** Build the target-owned identity for one field, independent of host keys. **/
	public static function fieldIdentity(owner:String, name:String, isStatic:Bool):String
		return required(owner, "field owner") + "::" + (isStatic ? "static" : "instance") + "::" + required(name, "field name");

	/** Build the target-owned identity for one method signature. **/
	public static function methodIdentity(owner:String, name:String, isStatic:Bool, argumentTypes:Array<String>, returnType:String):String {
		final values = new Array<Null<String>>();
		values.push(required(owner, "method owner"));
		values.push(isStatic ? "static" : "instance");
		values.push(required(name, "method name"));
		addStrings(values, argumentTypes == null ? [] : argumentTypes);
		values.push(required(returnType, "method return type"));
		return required(owner, "method owner") + "::method::" + Sha256.encode(encode(values));
	}

	public static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target declaration request requires " + label;
		return normalized;
	}

	public static function flag(value:Bool):String
		return value ? "1" : "0";

	public static function addStrings(out:Array<Null<String>>, values:Array<String>):Void {
		out.push(Std.string(values.length));
		for (value in values)
			out.push(value);
	}

	public static function rejectDuplicateIdentities(identities:Array<String>, kind:String, owner:String):Void {
		var previous:Null<String> = null;
		for (identity in identities) {
			if (identity == previous)
				throw 'OCaml target declaration request contains duplicate ${kind} ${identity} in ${owner}';
			previous = identity;
		}
	}

	public static function encode(values:Array<Null<String>>):String {
		final out = new StringBuf();
		for (value in values)
			if (value == null) {
				out.add("n;");
			} else {
				out.add("s");
				out.add(value.length);
				out.add(":");
				out.add(value);
				out.add(";");
			}
		return out.toString();
	}
}
