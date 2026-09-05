package reflaxe.ocaml.target;

import haxe.crypto.Sha256;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetClassFact;

/**
	The first complete, host-neutral program input for the standalone OCaml target.

	This revision deliberately accepts one primary class containing only static,
	initialized final fields and static zero-argument `Void` functions. Both host
	adapters may carry larger compiler programs into this constructor, but the
	semantic identity contains only the selected main class and its exact bodies.
**/
class OcamlTargetProgramRequest {
	public static inline final SCHEMA_REVISION = "reflaxe-ocaml-target-program-v1";

	public final hostProgramRevision:String;
	public final mainModuleId:String;
	public final mainClass:OcamlTargetClassFact;

	final fieldInitializers:Array<OcamlTargetFieldInitializerFact>;
	final functions:Array<OcamlTargetFunctionFact>;
	final canonicalIdentity:String;

	public function new(hostProgramRevision:String, mainModuleId:String, declarations:OcamlTargetDeclarationRequest,
			fieldInitializers:Array<OcamlTargetFieldInitializerFact>, functions:Array<OcamlTargetFunctionFact>) {
		final normalizedHostRevision = required(hostProgramRevision, "host program revision");
		final normalizedMainModuleId = required(mainModuleId, "main module ID");
		if (declarations == null)
			throw "OCaml target program requires declaration facts";
		final selectedMainClass = selectMainClass(declarations.copyClasses(), normalizedMainModuleId);
		final selectedClassName = mainClassName(selectedMainClass);
		final selectedFieldInitializers = selectFieldInitializers(fieldInitializers, normalizedMainModuleId, selectedClassName);
		final selectedFunctions = selectFunctions(functions, normalizedMainModuleId, selectedClassName);
		validateRevisionOne(selectedMainClass, selectedFieldInitializers, selectedFunctions);
		this.hostProgramRevision = normalizedHostRevision;
		this.mainModuleId = normalizedMainModuleId;
		this.mainClass = selectedMainClass;
		this.fieldInitializers = selectedFieldInitializers;
		this.functions = selectedFunctions;

		final identityFacts = new Array<Null<String>>();
		identityFacts.push(SCHEMA_REVISION);
		identityFacts.push(this.mainModuleId);
		identityFacts.push(mainClass.getCanonicalIdentity());
		identityFacts.push(Std.string(this.fieldInitializers.length));
		for (field in this.fieldInitializers)
			identityFacts.push(field.getCanonicalIdentity());
		identityFacts.push(Std.string(this.functions.length));
		for (fn in this.functions)
			identityFacts.push(fn.getCanonicalIdentity());
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(identityFacts));
	}

	public function copyFieldInitializers():Array<OcamlTargetFieldInitializerFact>
		return fieldInitializers.copy();

	public function copyFunctions():Array<OcamlTargetFunctionFact>
		return functions.copy();

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	/** Return the exact class component used by the normalized program identity. **/
	public function getMainClassIdentity():String
		return mainClass.getCanonicalIdentity();

	/** Return the length-delimited class facts behind the component identity. **/
	public function copyMainClassIdentityFacts():Array<Null<String>> {
		final facts = new Array<Null<String>>();
		mainClass.addIdentity(facts);
		return facts;
	}

	/** Return the ordered field components used by the normalized program identity. **/
	public function copyFieldIdentities():Array<String>
		return [for (field in fieldInitializers) field.getCanonicalIdentity()];

	/** Return the ordered function components used by the normalized program identity. **/
	public function copyFunctionIdentities():Array<String>
		return [for (fn in functions) fn.getCanonicalIdentity()];

	static function selectMainClass(classes:Array<OcamlTargetClassFact>, mainModuleId:String):OcamlTargetClassFact {
		var selected:Null<OcamlTargetClassFact> = null;
		for (candidate in classes) {
			if (candidate.moduleIdentity != mainModuleId || candidate.canonicalIdentity != mainModuleId)
				continue;
			if (selected != null)
				throw 'OCaml target program found more than one primary class for "$mainModuleId"';
			selected = candidate;
		}
		if (selected == null)
			throw 'OCaml target program cannot find primary class "$mainModuleId"';
		return selected;
	}

	static function selectFieldInitializers(values:Array<OcamlTargetFieldInitializerFact>, mainModuleId:String,
			mainClassName:String):Array<OcamlTargetFieldInitializerFact> {
		final selected = new Array<OcamlTargetFieldInitializerFact>();
		if (values != null)
			for (value in values) {
				if (value == null)
					throw "OCaml target program contains a null field initializer";
				if (value.moduleId == mainModuleId && value.sourceTypeName == mainClassName)
					selected.push(value);
			}
		selected.sort((left, right) -> compareText(left.getTargetIdentity(), right.getTargetIdentity()));
		return uniqueFields(selected);
	}

	static function selectFunctions(values:Array<OcamlTargetFunctionFact>, mainModuleId:String, mainClassName:String):Array<OcamlTargetFunctionFact> {
		final selected = new Array<OcamlTargetFunctionFact>();
		if (values != null)
			for (value in values) {
				if (value == null)
					throw "OCaml target program contains a null function";
				if (value.moduleId == mainModuleId && value.sourceTypeName == mainClassName)
					selected.push(value);
			}
		selected.sort((left, right) -> compareText(left.getTargetIdentity(), right.getTargetIdentity()));
		return uniqueFunctions(selected);
	}

	static function validateRevisionOne(mainClass:OcamlTargetClassFact, fieldInitializers:Array<OcamlTargetFieldInitializerFact>,
			functions:Array<OcamlTargetFunctionFact>):Void {
		if (mainClass.copyTypeParameters().length != 0
			|| mainClass.superClassIdentity != null
			|| mainClass.superTypeIdentity != null
			|| mainClass.superTypeDisplay != null)
			throw "OCaml target program revision 1 requires a non-generic primary class without a superclass";

		final fieldsByName:Map<String, OcamlTargetFieldInitializerFact> = [];
		for (field in fieldInitializers)
			fieldsByName.set(field.sourceFieldName, field);
		for (declaration in mainClass.copyFields()) {
			final initializer = fieldsByName.get(declaration.name);
			if (initializer == null)
				throw 'OCaml target program revision 1 cannot lower field "${declaration.name}"';
			if (!declaration.isStatic
				|| !declaration.isFinal
				|| !declaration.hasInitializer
				|| declaration.isInline
				|| declaration.propertyGet != "normal"
				|| declaration.propertySet != "never"
				|| declaration.noImportGlobal
				|| initializer.semanticTypeDisplay != declaration.typeDisplay)
				throw 'OCaml target program revision 1 cannot lower field "${declaration.name}"';
			fieldsByName.remove(declaration.name);
		}
		for (name in fieldsByName.keys())
			throw 'OCaml target program received an initializer for unknown field "$name"';

		final functionsByName:Map<String, OcamlTargetFunctionFact> = [];
		for (fn in functions)
			functionsByName.set(fn.sourceFunctionName, fn);
		for (declaration in mainClass.copyMethods()) {
			final fn = functionsByName.get(declaration.name);
			if (!declaration.isStatic
				|| declaration.copyTypeParameters().length != 0
				|| declaration.copyArguments().length != 0
				|| declaration.returnTypeDisplay != "Void"
				|| !declaration.hasBody
				|| declaration.isInline
				|| declaration.isDynamic
				|| declaration.isEnumConstructor
				|| declaration.noImportGlobal
				|| fn == null)
				throw 'OCaml target program revision 1 cannot lower function "${declaration.name}"';
			functionsByName.remove(declaration.name);
		}
		for (name in functionsByName.keys())
			throw 'OCaml target program received a body for unknown function "$name"';
		if (findFunction(functions, "main") == null)
			throw "OCaml target program revision 1 requires a static main function";
	}

	static function findFunction(functions:Array<OcamlTargetFunctionFact>, name:String):Null<OcamlTargetFunctionFact> {
		for (fn in functions)
			if (fn.sourceFunctionName == name)
				return fn;
		return null;
	}

	static function mainClassName(mainClass:OcamlTargetClassFact):String {
		final separator = mainClass.canonicalIdentity.lastIndexOf(".");
		return separator < 0 ? mainClass.canonicalIdentity : mainClass.canonicalIdentity.substr(separator + 1);
	}

	static function uniqueFields(values:Array<OcamlTargetFieldInitializerFact>):Array<OcamlTargetFieldInitializerFact> {
		final result = new Array<OcamlTargetFieldInitializerFact>();
		var previous:Null<OcamlTargetFieldInitializerFact> = null;
		for (value in values) {
			if (previous == null || previous.getTargetIdentity() != value.getTargetIdentity()) {
				result.push(value);
				previous = value;
			} else if (previous.getCanonicalIdentity() != value.getCanonicalIdentity()) {
				throw 'OCaml target program contains conflicting field facts for "${value.getTargetIdentity()}"';
			}
		}
		return result;
	}

	static function uniqueFunctions(values:Array<OcamlTargetFunctionFact>):Array<OcamlTargetFunctionFact> {
		final result = new Array<OcamlTargetFunctionFact>();
		var previous:Null<OcamlTargetFunctionFact> = null;
		for (value in values) {
			if (previous == null || previous.getTargetIdentity() != value.getTargetIdentity()) {
				result.push(value);
				previous = value;
			} else if (previous.getCanonicalIdentity() != value.getCanonicalIdentity()) {
				throw 'OCaml target program contains conflicting function facts for "${value.getTargetIdentity()}"';
			}
		}
		return result;
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target program requires " + label;
		return normalized;
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
