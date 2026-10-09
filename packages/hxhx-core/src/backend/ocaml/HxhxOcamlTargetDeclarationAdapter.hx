package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetDeclarationRequest;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetArgumentInput;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetClassInput;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetFieldInput;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetMethodInput;

/**
	Copies sealed native `hxhx` class facts into a target-owned declaration request.

	This is the shared target declaration boundary for reading the observation-only
	class catalog. It copies every admitted value into `OcamlTargetDeclarationRequest`,
	so downstream target code cannot retain native compiler objects. The adapter
	selects no OCaml behavior and fails when typing did not provide exact facts.
	Stage3 enum emission uses its separate `Stage3OcamlEnumPlan` until the shared
	program request can represent enum construction and payload matching.
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
		// Native lookup identities include a secondary type's module. The target
		// contract separates that module from the package-qualified declared name.
		final packageParts = facts.getModuleIdentity().split(".");
		packageParts.pop();
		final sourceTypeName = packageParts.concat([facts.getDeclaredName()]).join(".");
		final owner = OcamlTargetDeclarationRequest.classIdentity(facts.getModuleIdentity(), sourceTypeName);
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
			// Native constructor signatures describe the allocated instance. This
			// declaration contract describes the constructor body, which returns Void
			// in the public stock-Haxe API. Allocation remains a separate expression.
			final resultDisplay = method.name == "new"
				&& !method.isStatic
				&& !method.isEnumConstructor ? "Void" : method.returnTypeDisplay;
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
					[for (argument in arguments) argumentIdentity(argument)], resultDisplay),
				name: method.name,
				typeParameters: [for (parameter in method.typeParameters) parameter.getName()],
				arguments: arguments,
				returnTypeIdentity: resultDisplay,
				returnTypeDisplay: resultDisplay,
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
			isInterface: facts.getIsInterface(),
			isExtern: facts.getIsExtern(),
			interfaceTypeDisplays: [for (type in facts.getInterfaceTypes()) type.getCanonicalDisplay()],
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
