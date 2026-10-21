package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlExpr.*;
import reflaxe.ocaml.ast.OcamlPat.*;
import reflaxe.ocaml.ast.OcamlConst.*;
import reflaxe.ocaml.ast.OcamlTypeExpr.*;
import reflaxe.ocaml.lowered.OcamlMethodDispatchClassPlan;
import reflaxe.ocaml.lowered.OcamlMethodDispatchClassPlan.sealClassMethodRegistration;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/**
	Builds registration before an allocated record can enter user code.

	Each binder recovers the implementation owner's record prefix from the exact
	allocated class checked by HxMethodDispatch.bind. The shared method catalog
	selects the effective override. Explicit argument/result types check the actual
	implementation during native compilation, without its legacy slot wrapper. The
	registry stores these binders, not an instance or an identity-changing wrapper.
**/
function buildClassMethodRegistration(plan:OcamlMethodDispatchClassPlan, classMarker:OcamlExpr, context:CompilationContext, profile:String):OcamlExpr {
	final checked = sealClassMethodRegistration(plan.marker, plan.recordSize, plan.entries);
	if (checked.registryRevision != plan.registryRevision)
		throw "reflaxe.ocaml [ocaml-method-dispatch:changed-registration]: class entries changed";
	final id = plan.marker.id + ":method-registration";
	final revision = plan.registryRevision + ":" + plan.marker.emissionRole;
	final requirement:OcamlRuntimeRequirement = {
		id: id + ":runtime",
		sourceKind: OcamlRuntimeRequirementSourceKind.RepresentationDecision,
		sourceId: plan.marker.sourceDeclarationId,
		source: plan.marker.source,
		semanticCapability: "haxe-native-method-dispatch",
		cause: OcamlRuntimeRequirementCause.RepresentationDecision,
		decisionId: id,
		subject: {
			kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
			id: plan.marker.sourceDeclarationId
		},
		implementationFeature: "haxe-native-method-dispatch-v1",
		rootModules: ["HxMethodDispatch"],
		profileEligibility: ["metal", "portable"],
		explanation: "The selected native class record installs its checked method contracts before allocation can reach user code."
	};
	final occurrence:OcamlRuntimeUseOccurrence = {
		id: id + ":ensure",
		planRevision: revision,
		ownerId: id,
		requirementId: requirement.id,
		domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
		exactSymbol: "HxMethodDispatch.ensure",
		role: "class-method-registration",
		order: 0,
		source: plan.marker.source,
		profileEligibility: ["metal", "portable"],
		cardinality: 1
	};
	final authority = new OcamlRuntimeUseAuthority(revision, profile, [requirement], [occurrence], context.finalRuntimeUses);
	final identifier = ERuntimeIdent(authority.expressionIdentifier(occurrence.id, revision, occurrence.exactSymbol));
	// Binder annotations have separately checked representation occurrences. The
	// final output authority reconciles their complete tree with this identifier.
	authority.reconcileExpression(identifier);
	context.runtimeRequirements.record(requirement);
	final entries:Array<OcamlExpr> = [];
	for (entry in plan.entries) {
		final parameters:Array<OcamlPat> = [];
		final arguments:Array<OcamlExpr> = [EIdent("__hx_method_self")];
		for (index in 0...entry.nativeSignature.parameters.length) {
			final name = "__hx_method_arg" + index;
			parameters.push(PAnnot(PVar(name), entry.nativeSignature.parameters[index]));
			arguments.push(EIdent(name));
		}
		if (parameters.length == 0) {
			parameters.push(PConst(CUnit));
			arguments.push(EConst(CUnit));
		}
		final owner = entry.implementationOwner;
		final ownerModule = context.ocamlModuleNameForModuleId(owner.module);
		final sameModule = context.currentModuleId == owner.module;
		final ownerType = context.scopedInstanceTypeName(owner.module, owner.name);
		final ownerFullName = owner.pack.concat([owner.name]).join(".");
		final methodName = context.scopedValueName(owner.module, owner.name,
			entry.signature.methodName + (context.dispatchTypes.exists(ownerFullName) ? "__impl" : ""));
		final method = sameModule ? EIdent(methodName) : EField(EIdent(ownerModule), methodName);
		final invocation = EAnnot(EApp(method, arguments), entry.nativeSignature.result);
		final bound = EFun(parameters, invocation);
		final recover = EAnnot(EApp(EIdent("Obj.obj"), [EIdent("__hx_method_receiver")]), TIdent(sameModule ? ownerType : ownerModule + "." + ownerType));
		final binder = EFun([PAnnot(PVar("__hx_method_receiver"), TIdent("Obj.t"))],
			ELet("__hx_method_self", recover, EApp(EIdent("Obj.repr"), [bound]), false));
		entries.push(ETuple([EConst(CString(entry.signature.key)), binder]));
	}
	return EApp(identifier, [
		classMarker,
		EConst(CString(plan.registryRevision)),
		EConst(CInt(plan.recordSize)),
		EFun([PConst(CUnit)], EList(entries))
	]);
}
#end
