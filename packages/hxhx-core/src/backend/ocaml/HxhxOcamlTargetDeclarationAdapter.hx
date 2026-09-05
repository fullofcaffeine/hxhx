package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetDeclarationRequest;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetArgumentInput;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetClassInput;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetFieldInput;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetMethodInput;

/**
	Copies sealed native `hxhx` class facts into the standalone OCaml target input.

	This adapter selects no OCaml behavior. It only removes native compiler objects
	from the boundary and fails when typing did not provide exact semantic facts.
**/
class HxhxOcamlTargetDeclarationAdapter {
	public static function fromModules(hostProgramRevision:String, modules:Array<TypedBackendModuleProjection>):OcamlTargetDeclarationRequest {
		if (modules == null)
			throw "native OCaml target declaration adapter requires typed modules";
		final classes = new Array<OcamlTargetClassInput>();
		for (moduleProjection in modules) {
			if (moduleProjection == null)
				throw "native OCaml target declaration adapter received a null module";
			for (classProjection in moduleProjection.getClasses())
				classes.push(copyClass(classProjection.requireSemanticFacts()));
		}
		return new OcamlTargetDeclarationRequest(hostProgramRevision, classes);
	}

	/** Copy an already sealed class-fact catalog without rebuilding projections. **/
	public static function fromClassFacts(hostProgramRevision:String, facts:Array<TypedBackendClassSemanticFacts>):OcamlTargetDeclarationRequest {
		if (facts == null)
			throw "native OCaml target declaration adapter requires class facts";
		return new OcamlTargetDeclarationRequest(hostProgramRevision, [for (classFacts in facts) copyClass(classFacts)]);
	}

	static function copyClass(facts:TypedBackendClassSemanticFacts):OcamlTargetClassInput {
		final owner = OcamlTargetDeclarationRequest.classIdentity(facts.getModuleIdentity(), facts.getClassIdentity());
		final fields = new Array<OcamlTargetFieldInput>();
		for (field in facts.copyFields())
			fields.push({
				canonicalIdentity: OcamlTargetDeclarationRequest.fieldIdentity(owner, field.name, field.isStatic),
				name: field.name,
				typeIdentity: field.typeDisplay,
				typeDisplay: field.typeDisplay,
				isStatic: field.isStatic,
				isPublic: field.isPublic,
				isFinal: field.isFinal,
				isInline: field.isInline,
				hasInitializer: field.hasInitializer,
				propertyGet: field.propertyGet.length == 0 ? "normal" : field.propertyGet,
				propertySet: field.propertySet.length == 0 ? (field.isFinal ? "never" : "normal") : field.propertySet,
				noImportGlobal: field.noImportGlobal
			});
		final methods = new Array<OcamlTargetMethodInput>();
		for (method in facts.copyMethods()) {
			final arguments = new Array<OcamlTargetArgumentInput>();
			for (argument in method.arguments)
				arguments.push({
					name: argument.name,
					typeIdentity: argument.typeDisplay,
					typeDisplay: argument.typeDisplay,
					isOptional: argument.isOptional,
					isRest: argument.isRest
				});
			methods.push({
				canonicalIdentity: OcamlTargetDeclarationRequest.methodIdentity(owner, method.name, method.isStatic,
					[for (argument in arguments) argumentIdentity(argument)], method.returnTypeDisplay),
				name: method.name,
				typeParameters: [for (parameter in method.typeParameters) parameter.getName()],
				arguments: arguments,
				returnTypeIdentity: method.returnTypeDisplay,
				returnTypeDisplay: method.returnTypeDisplay,
				isStatic: method.isStatic,
				isPublic: method.isPublic,
				isInline: method.isInline,
				isDynamic: method.isDynamic,
				hasBody: method.hasBody,
				isEnumConstructor: method.isEnumConstructor,
				noImportGlobal: method.noImportGlobal
			});
		}
		return {
			canonicalIdentity: owner,
			moduleIdentity: facts.getModuleIdentity(),
			typeParameters: facts.getTypeParameters(),
			superClassIdentity: facts.getSuperClassIdentity(),
			superTypeIdentity: facts.getSuperTypeIdentity(),
			superTypeDisplay: facts.getSuperTypeDisplay(),
			fields: fields,
			methods: methods
		};
	}

	static function argumentIdentity(argument:OcamlTargetArgumentInput):String
		return argument.typeIdentity + ":optional=" + (argument.isOptional ? "1" : "0") + ":rest=" + (argument.isRest ? "1" : "0");
}
