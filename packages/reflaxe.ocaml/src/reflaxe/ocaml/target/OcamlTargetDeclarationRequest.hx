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
	/**
		The reflected source name, or an empty string for a synthetic positional
		parameter whose Haxe macro fact has no name.
	**/
	public final name:String;

	public final typeIdentity:String;
	public final typeDisplay:String;
	public final isOptional:Bool;
	public final isRest:Bool;

	public function new(input:OcamlTargetArgumentInput) {
		name = input.name == null ? "" : input.name;
		typeIdentity = OcamlTargetDeclarationCodec.required(input.typeIdentity, "argument type identity");
		typeDisplay = OcamlTargetDeclarationCodec.required(input.typeDisplay, "argument type display");
		isOptional = input.isOptional;
		isRest = input.isRest;
	}

	public function addIdentity(out:Array<Null<String>>):Void {
		out.push(name);
		out.push(typeIdentity);
		out.push(typeDisplay);
		out.push(OcamlTargetDeclarationCodec.flag(isOptional));
		out.push(OcamlTargetDeclarationCodec.flag(isRest));
	}
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
		canonicalIdentity = OcamlTargetDeclarationCodec.required(input.canonicalIdentity, "field identity");
		name = OcamlTargetDeclarationCodec.required(input.name, "field name");
		typeIdentity = OcamlTargetDeclarationCodec.required(input.typeIdentity, "field type identity");
		typeDisplay = OcamlTargetDeclarationCodec.required(input.typeDisplay, "field type display");
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
		out.push(OcamlTargetDeclarationCodec.flag(isStatic));
		out.push(OcamlTargetDeclarationCodec.flag(isPublic));
		out.push(OcamlTargetDeclarationCodec.flag(isFinal));
		out.push(OcamlTargetDeclarationCodec.flag(isInline));
		out.push(OcamlTargetDeclarationCodec.flag(hasInitializer));
		out.push(propertyGet);
		out.push(propertySet);
		out.push(OcamlTargetDeclarationCodec.flag(noImportGlobal));
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
		canonicalIdentity = OcamlTargetDeclarationCodec.required(input.canonicalIdentity, "method identity");
		name = OcamlTargetDeclarationCodec.required(input.name, "method name");
		typeParameters = copyRequired(input.typeParameters, "method type parameter");
		arguments = input.arguments == null ? [] : [for (argument in input.arguments) new OcamlTargetArgumentFact(argument)];
		returnTypeIdentity = OcamlTargetDeclarationCodec.required(input.returnTypeIdentity, "method return type identity");
		returnTypeDisplay = OcamlTargetDeclarationCodec.required(input.returnTypeDisplay, "method return type display");
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
		OcamlTargetDeclarationCodec.addStrings(out, typeParameters);
		out.push(returnTypeIdentity);
		out.push(returnTypeDisplay);
		out.push(OcamlTargetDeclarationCodec.flag(isStatic));
		out.push(OcamlTargetDeclarationCodec.flag(isPublic));
		out.push(OcamlTargetDeclarationCodec.flag(isInline));
		out.push(OcamlTargetDeclarationCodec.flag(isDynamic));
		out.push(OcamlTargetDeclarationCodec.flag(hasBody));
		out.push(OcamlTargetDeclarationCodec.flag(isEnumConstructor));
		out.push(OcamlTargetDeclarationCodec.flag(noImportGlobal));
		out.push(Std.string(arguments.length));
		for (argument in arguments)
			argument.addIdentity(out);
	}

	static function copyRequired(values:Array<String>, label:String):Array<String> {
		if (values == null)
			return [];
		return [for (value in values) OcamlTargetDeclarationCodec.required(value, label)];
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
		canonicalIdentity = OcamlTargetDeclarationCodec.required(input.canonicalIdentity, "class identity");
		moduleIdentity = OcamlTargetDeclarationCodec.required(input.moduleIdentity, "module identity");
		typeParameters = input.typeParameters == null ? [] : [
			for (value in input.typeParameters)
				OcamlTargetDeclarationCodec.required(value, "class type parameter")
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
		fields = uniqueFields(copiedFields, canonicalIdentity);
		methods = uniqueMethods(copiedMethods, canonicalIdentity);
	}

	public function copyTypeParameters():Array<String>
		return typeParameters.copy();

	public function copyFields():Array<OcamlTargetFieldFact>
		return fields.copy();

	public function copyMethods():Array<OcamlTargetMethodFact>
		return methods.copy();

	/** Return this class's semantic declaration identity without host provenance. **/
	public function getCanonicalIdentity():String {
		final facts = new Array<Null<String>>();
		addIdentity(facts);
		return haxe.crypto.Sha256.encode(OcamlTargetDeclarationCodec.encode(facts));
	}

	public function addIdentity(out:Array<Null<String>>):Void {
		out.push(canonicalIdentity);
		out.push(moduleIdentity);
		OcamlTargetDeclarationCodec.addStrings(out, typeParameters);
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

	static function uniqueFields(values:Array<OcamlTargetFieldFact>, ownerIdentity:String):Array<OcamlTargetFieldFact> {
		final result = new Array<OcamlTargetFieldFact>();
		var previous:Null<OcamlTargetFieldFact> = null;
		for (value in values) {
			if (previous == null || previous.canonicalIdentity != value.canonicalIdentity) {
				result.push(value);
				previous = value;
			} else if (fieldFingerprint(previous) != fieldFingerprint(value)) {
				throw 'OCaml target declaration request contains conflicting field ${value.canonicalIdentity} in ${ownerIdentity}';
			}
		}
		return result;
	}

	static function uniqueMethods(values:Array<OcamlTargetMethodFact>, ownerIdentity:String):Array<OcamlTargetMethodFact> {
		final result = new Array<OcamlTargetMethodFact>();
		var previous:Null<OcamlTargetMethodFact> = null;
		for (value in values) {
			if (previous == null || previous.canonicalIdentity != value.canonicalIdentity) {
				result.push(value);
				previous = value;
			} else if (methodFingerprint(previous) != methodFingerprint(value)) {
				throw 'OCaml target declaration request contains conflicting method ${value.canonicalIdentity} in ${ownerIdentity}';
			}
		}
		return result;
	}

	static function fieldFingerprint(value:OcamlTargetFieldFact):String {
		final facts = new Array<Null<String>>();
		value.addIdentity(facts);
		return OcamlTargetDeclarationCodec.encode(facts);
	}

	static function methodFingerprint(value:OcamlTargetMethodFact):String {
		final facts = new Array<Null<String>>();
		value.addIdentity(facts);
		return OcamlTargetDeclarationCodec.encode(facts);
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
		this.hostProgramRevision = OcamlTargetDeclarationCodec.required(hostProgramRevision, "host program revision");
		final copiedClasses = inputs == null ? [] : [for (input in inputs) new OcamlTargetClassFact(input)];
		copiedClasses.sort((left, right) -> Reflect.compare(left.canonicalIdentity, right.canonicalIdentity));
		classes = uniqueClasses(copiedClasses);
		final identityFacts = new Array<Null<String>>();
		identityFacts.push(SCHEMA_REVISION);
		identityFacts.push(Std.string(classes.length));
		for (classFact in classes)
			classFact.addIdentity(identityFacts);
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(identityFacts));
	}

	/** Return the semantic identity shared by equivalent stock and native inputs. **/
	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function copyClasses():Array<OcamlTargetClassFact>
		return classes.copy();

	/** Distinguish same-named secondary or private types owned by different modules. **/
	public static function classIdentity(moduleIdentity:String, typeIdentity:String):String {
		final moduleName = OcamlTargetDeclarationCodec.required(moduleIdentity, "class module identity");
		final typeName = OcamlTargetDeclarationCodec.required(typeIdentity, "class type identity");
		return moduleName == typeName ? typeName : moduleName + "#" + typeName;
	}

	static function uniqueClasses(values:Array<OcamlTargetClassFact>):Array<OcamlTargetClassFact> {
		final result = new Array<OcamlTargetClassFact>();
		var previous:Null<OcamlTargetClassFact> = null;
		for (value in values) {
			if (previous == null || previous.canonicalIdentity != value.canonicalIdentity) {
				result.push(value);
				previous = value;
			} else if (classFingerprint(previous) != classFingerprint(value)) {
				throw 'OCaml target declaration request contains conflicting class ${value.canonicalIdentity} in program';
			}
		}
		return result;
	}

	static function classFingerprint(value:OcamlTargetClassFact):String {
		final facts = new Array<Null<String>>();
		value.addIdentity(facts);
		return OcamlTargetDeclarationCodec.encode(facts);
	}

	/** Build the target-owned identity for one field, independent of host keys. **/
	public static function fieldIdentity(owner:String, name:String, isStatic:Bool):String
		return OcamlTargetDeclarationCodec.required(owner, "field owner")
			+ "::"
			+ (isStatic ? "static" : "instance")
			+ "::"
			+ OcamlTargetDeclarationCodec.required(name, "field name");

	/** Build the target-owned identity for one method signature. **/
	public static function methodIdentity(owner:String, name:String, isStatic:Bool, argumentTypes:Array<String>, returnType:String):String {
		final values = new Array<Null<String>>();
		values.push(OcamlTargetDeclarationCodec.required(owner, "method owner"));
		values.push(isStatic ? "static" : "instance");
		values.push(OcamlTargetDeclarationCodec.required(name, "method name"));
		OcamlTargetDeclarationCodec.addStrings(values, argumentTypes == null ? [] : argumentTypes);
		values.push(OcamlTargetDeclarationCodec.required(returnType, "method return type"));
		return OcamlTargetDeclarationCodec.required(owner, "method owner") + "::method::" + Sha256.encode(OcamlTargetDeclarationCodec.encode(values));
	}
}
