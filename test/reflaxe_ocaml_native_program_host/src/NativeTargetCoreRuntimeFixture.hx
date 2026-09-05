import reflaxe.ocaml.target.OcamlTargetBindingFact;
import reflaxe.ocaml.target.OcamlTargetBindingFact.OcamlTargetBindingRole;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest;
import reflaxe.ocaml.target.OcamlTargetExpressionFact;
import reflaxe.ocaml.target.OcamlTargetExpressionPath;
import reflaxe.ocaml.target.OcamlTargetFieldInitializerFact;
import reflaxe.ocaml.target.OcamlTargetFieldInitializerFact.OcamlTargetFieldInitializerRole;
import reflaxe.ocaml.target.OcamlTargetFunctionFact;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionRole;
import reflaxe.ocaml.target.OcamlTargetLiteralFact;
import reflaxe.ocaml.target.OcamlTargetProgramCore;
import reflaxe.ocaml.target.OcamlTargetProgramCore.OcamlTargetProgramPublisher;
import reflaxe.ocaml.target.OcamlTargetProgramRequest;

/** Executes the host-neutral target core after this fixture is compiled to OCaml. **/
class NativeTargetCoreRuntimeFixture {
	static function main():Void {
		final args = Sys.args();
		if (args.length != 1)
			throw "usage: NativeTargetCoreRuntimeFixture <output-directory>";
		final fieldSignature:reflaxe.ocaml.target.OcamlTargetFieldInitializerFact.OcamlTargetFieldInitializerSignature = {
			moduleId: "Main",
			sourceTypeName: "Main",
			sourceFieldName: "value",
			role: OcamlTargetFieldInitializerRole.StaticField,
			semanticTypeDisplay: "Int"
		};
		final fieldOwner = OcamlTargetFieldInitializerFact.identityFor(fieldSignature);
		final bindingPath = OcamlTargetExpressionPath.indexed(OcamlTargetExpressionPath.ROOT, "block-item", 0);
		final binding = new OcamlTargetBindingFact(fieldOwner, OcamlTargetExpressionPath.child(bindingPath, "binding"), OcamlTargetBindingRole.Variable,
			"inner", "Int");
		final initializer = OcamlTargetExpressionFact.literalExpression(OcamlTargetExpressionPath.child(bindingPath, "initializer"),
			OcamlTargetLiteralFact.intLiteral(7, "Int"));
		final declaration = OcamlTargetExpressionFact.variableDeclaration(bindingPath, binding, initializer);
		final read = OcamlTargetExpressionFact.localRead(OcamlTargetExpressionPath.indexed(OcamlTargetExpressionPath.ROOT, "block-item", 1), "Int", binding);
		final field = new OcamlTargetFieldInitializerFact(fieldSignature,
			OcamlTargetExpressionFact.block(OcamlTargetExpressionPath.ROOT, "Int", [declaration, read]));
		final functionSignature:reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionSignature = {
			moduleId: "Main",
			sourceTypeName: "Main",
			sourceFunctionName: "main",
			role: OcamlTargetFunctionRole.StaticFunction,
			argumentTypeDisplays: [],
			returnTypeDisplay: "Void"
		};
		final fn = new OcamlTargetFunctionFact(functionSignature, OcamlTargetExpressionFact.block(OcamlTargetExpressionPath.ROOT, "Void", []));
		final declarations = new OcamlTargetDeclarationRequest("native-target-core-runtime", [
			{
				canonicalIdentity: "Main",
				moduleIdentity: "Main",
				typeParameters: [],
				fields: [
					{
						canonicalIdentity: OcamlTargetDeclarationRequest.fieldIdentity("Main", "value", true),
						name: "value",
						typeIdentity: "Int",
						typeDisplay: "Int",
						isStatic: true,
						isPublic: false,
						isFinal: true,
						isInline: false,
						hasInitializer: true,
						propertyGet: "normal",
						propertySet: "never",
						noImportGlobal: false
					}
				],
				methods: [
					{
						canonicalIdentity: OcamlTargetDeclarationRequest.methodIdentity("Main", "main", true, [], "Void"),
						name: "main",
						typeParameters: [],
						arguments: [],
						returnTypeIdentity: "Void",
						returnTypeDisplay: "Void",
						isStatic: true,
						isPublic: false,
						isInline: false,
						isDynamic: false,
						hasBody: true,
						isEnumConstructor: false,
						noImportGlobal: false
					}
				]
			}
		]);
		final request = new OcamlTargetProgramRequest("native-target-core-runtime", "Main", declarations, [field], [fn]);
		final plan = OcamlTargetProgramCore.lower(request);
		final executable = OcamlTargetProgramPublisher.publish(plan, args[0], "native-target-core-runtime", true);
		Sys.println("native_target_core_executable=" + executable);
	}
}
