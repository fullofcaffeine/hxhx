package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlExpr.*;
import reflaxe.ocaml.ast.OcamlConst.*;
import reflaxe.ocaml.ast.OcamlTypeExpr.*;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlMethodDispatchProgram;
import reflaxe.ocaml.lowered.OcamlMethodDispatchRootPlan.OcamlMethodDispatchUse;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature.selectMethodSignature;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/**
	Recovers a class method after its class and complete signature pass runtime checks.

	The declaration projection supplies the same native carriers used by the
	class registration. A capture binds its receiver immediately. A direct call
	evaluates that receiver and then its arguments once, in source order. No
	interface record layout or unchecked virtual slot participates in recovery.
	A method-only structural consumer also accepts an ordinary anonymous table,
	whose required field must contain a callable value. Class-backed tables cannot
	masquerade as native records at this boundary.
**/
function buildMethodDispatchUse(use:OcamlMethodDispatchUse, context:CompilationContext, representations:OcamlRepresentationRegistry,
		program:OcamlMethodDispatchProgram, nominalType:Type->OcamlTypeExpr, build:TypedExpr->OcamlExpr, coerce:Type->TypedExpr->OcamlExpr,
		fresh:String->String, profile:String):OcamlExpr {
	final method = switch (TypeTools.follow(use.field.type)) {
		case TFun(arguments, result): {arguments: arguments, result: result};
		case _: throw "reflaxe.ocaml [ocaml-method-dispatch:not-method]: selected declaration is not callable";
	};
	final native = projectDeclarationSignature(method.arguments.map(argument -> argument.t), method.result, representations, nominalType, context);
	final signature = native == null ? null : selectMethodSignature(use.field, native, context.ocamlModuleNameForModuleId(context.currentModuleId));
	if (native == null || signature == null)
		throw 'reflaxe.ocaml [ocaml-method-dispatch:unsupported-signature]: ${use.receiverType}.${use.field.name} requires a closed native method signature';
	if (use.arguments != null && use.arguments.length != native.parameters.length)
		throw "reflaxe.ocaml [ocaml-method-dispatch:wrong-arity]: method call arguments differ from its declaration";
	if (use.contract != null)
		program.recordUse(use.contract, signature);
	final revision = "sha256:" + Sha256.encode([
		use.binding.programRevision,
		use.binding.bodyRevision,
		use.binding.pipelineRevision,
		use.id,
		signature.key
	].join("|"));
	final requirement:OcamlRuntimeRequirement = {
		id: use.id + ":runtime",
		sourceKind: OcamlRuntimeRequirementSourceKind.RepresentationDecision,
		sourceId: use.binding.functionId,
		source: use.source,
		semanticCapability: "haxe-native-method-dispatch",
		cause: OcamlRuntimeRequirementCause.RepresentationDecision,
		decisionId: use.id,
		subject: {
			kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
			id: use.receiverType
		},
		implementationFeature: "haxe-native-method-dispatch-v1",
		rootModules: ["HxMethodDispatch"],
		profileEligibility: ["metal", "portable"],
		explanation: "A method call checks the original class object and exact signature, or the callable field of an ordinary anonymous object."
	};
	final occurrence:OcamlRuntimeUseOccurrence = {
		id: use.id + ":bind",
		planRevision: revision,
		ownerId: use.id,
		requirementId: requirement.id,
		domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
		exactSymbol: use.contract == null ? "HxMethodDispatch.bind_structural" : "HxMethodDispatch.bind",
		role: "interface-method-binding",
		order: 0,
		source: use.source,
		profileEligibility: ["metal", "portable"],
		cardinality: 1
	};
	final authority = new OcamlRuntimeUseAuthority(revision, profile, [requirement], [occurrence], context.finalRuntimeUses);
	final identifier = ERuntimeIdent(authority.expressionIdentifier(occurrence.id, revision, occurrence.exactSymbol));
	authority.reconcileExpression(identifier);
	context.runtimeRequirements.record(requirement);
	var functionType = native.result;
	if (native.parameters.length == 0)
		functionType = TArrow(TIdent("unit"), functionType);
	else
		for (index in 0...native.parameters.length)
			functionType = TArrow(native.parameters[native.parameters.length - 1 - index], functionType);
	final receiver = fresh("method_receiver");
	final callable = fresh("method_callable");
	final lookupArguments:Array<OcamlExpr> = [EApp(EIdent("Obj.repr"), [EIdent(receiver)])];
	if (use.contract == null)
		lookupArguments.push(EConst(CString(use.field.name)));
	lookupArguments.push(EConst(CString(signature.key)));
	final bound = EAnnot(EApp(EIdent("Obj.obj"), [EApp(identifier, lookupArguments)]), functionType);
	var result:OcamlExpr = EIdent(callable);
	if (use.arguments != null) {
		final names = use.arguments.map(_ -> fresh("method_argument"));
		result = EApp(EIdent(callable), names.length == 0 ? [EConst(CUnit)] : names.map(name -> EIdent(name)));
		// Build values in source order too: their nested runtime occurrences are
		// registered while syntax is built, independently of target evaluation.
		final values = [
			for (index in 0...names.length)
				coerce(method.arguments[index].t, use.arguments[index])
		];
		for (index in 0...names.length) {
			final offset = names.length - 1 - index;
			result = ELet(names[offset], values[offset], result, false);
		}
	}
	return ELet(receiver, build(use.receiver), ELet(callable, bound, result, false), false);
}
#end
