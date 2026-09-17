#if macro
import haxe.macro.Context;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlNativeEnumRepresentation;
import reflaxe.ocaml.lowered.OcamlNullableEnumCarrier;
import reflaxe.ocaml.lowered.OcamlNullableEnumCarrier.OcamlNullableEnumCarrierReference;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
#end

/** Checks native enum identity separately from the still-required value producer proof. */
class EnumRepresentationFixture {
	#if macro
	static function expectRejected(check:Void->Void, message:String):Void {
		var rejected = false;
		try {
			check();
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw message;
	}

	public static function run():Void {
		final context = new CompilationContext();
		final descriptor = OcamlNativeEnumRepresentation.select(Context.getType("Payload"), context);
		if (descriptor == null
			|| descriptor.semanticTypeId != "Payload"
			|| descriptor.sourceModuleId != "Payload"
			|| descriptor.targetModuleName != "Payload"
			|| descriptor.targetTypeName != "payload")
			throw "the ordinary enum lost its declared variant identity";
		OcamlNativeEnumRepresentation.validate(descriptor);
		for (expression in [
			Context.typeExpr(macro Payload.Text("ok")),
			Context.typeExpr(macro(Payload.Empty))
		])
			if (OcamlNativeEnumRepresentation.selectDirectConstructor(expression, context) == null)
				throw "an explicit enum constructor lost its producer identity";
		// The unchecked cast is an intentional negative compiler-boundary input.
		// Its enum annotation must not authorize native identity conversion.
		for (expression in [
			Context.typeExpr(macro(cast "wrong" : Payload)),
			Context.typeExpr(macro {
				final value:Payload = Payload.Text("ok");
				value;
			})
		])
			if (OcamlNativeEnumRepresentation.selectDirectConstructor(expression, context) != null)
				throw "an enum annotation or retained local was mistaken for a direct constructor";
		final registry = new OcamlRepresentationRegistry();
		registry.beginProgram("enum-representation-fixture");
		final selected = registry.selectNativeEnum(descriptor);
		final nullable = registry.selectNullableNativeEnum(descriptor);
		final carrierReference = OcamlNullableEnumCarrier.create(descriptor, selected, nullable, "enum-representation-fixture", context);
		OcamlNullableEnumCarrier.requireCurrent(carrierReference, context, registry);
		final reverseRegistry = new OcamlRepresentationRegistry();
		reverseRegistry.beginProgram("enum-representation-fixture");
		final reverseNullable = reverseRegistry.selectNullableNativeEnum(descriptor);
		final reverseSelected = reverseRegistry.selectNativeEnum(descriptor);
		final reverseReference = OcamlNullableEnumCarrier.create(descriptor, reverseSelected, reverseNullable, "enum-representation-fixture", context);
		if (!OcamlNullableEnumCarrier.same(carrierReference, reverseReference))
			throw "nullable enum evidence changed with representation preparation order";
		final corruptedReference:OcamlNullableEnumCarrierReference = {
			modelRevision: carrierReference.modelRevision,
			revision: carrierReference.revision,
			descriptor: carrierReference.descriptor,
			inputRepresentationId: carrierReference.inputRepresentationId,
			inputRepresentationRevision: carrierReference.inputRepresentationRevision,
			outputRepresentationId: carrierReference.outputRepresentationId,
			outputRepresentationRevision: "sha256:corrupted",
			programRevision: carrierReference.programRevision,
			crossingModel: carrierReference.crossingModel,
			crossingRevision: carrierReference.crossingRevision
		};
		expectRejected(() -> OcamlNullableEnumCarrier.requireCurrent(corruptedReference, context, registry),
			"edited nullable enum evidence retained its carrier authority");
		if (!OcamlNativeEnumRepresentation.typeExpr(selected, "Reader").match(TIdent("Payload.payload"))
			|| !OcamlNativeEnumRepresentation.typeExpr(selected, "Payload").match(TIdent("payload")))
			throw "enum type materialization lost its same-module or qualified spelling";
		if (selected.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectNativeEnumCarrier
			|| selected.carrierTypeId != "payload"
			|| registry.monomorphicClassValue("Payload") != null)
			throw "native enum selection was confused with a class record";
		selected.profileEligibility.push("corrupted");
		final reread = registry.nativeEnumValue("Payload");
		if (reread == null || reread.profileEligibility.indexOf("corrupted") >= 0)
			throw "a copied enum representation changed the registry";
		for (type in [
			Context.resolveType(macro :Null<Payload>, Context.currentPos()),
			Context.getType("Int"),
			Context.resolveType(macro :haxe.ds.Option<Int>, Context.currentPos())
		])
			if (OcamlNativeEnumRepresentation.select(type, context) != null)
				throw "an unsupported nullable, primitive, or generic type gained a native enum representation";
		var rejected = false;
		try {
			OcamlNativeEnumRepresentation.validate({
				semanticTypeId: descriptor.semanticTypeId,
				sourceModuleId: descriptor.sourceModuleId,
				sourceTypeName: descriptor.sourceTypeName,
				targetModuleName: "Foreign",
				targetTypeName: descriptor.targetTypeName,
				revision: descriptor.revision
			});
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf("invalid-descriptor") >= 0;
		}
		if (!rejected)
			throw "an edited enum module retained its descriptor revision";
		context.fileIdOverrideByModuleId.set("Payload", "renamed_payload");
		final renamed = OcamlNativeEnumRepresentation.select(Context.getType("Payload"), context);
		if (renamed == null || renamed.targetModuleName != "Renamed_payload" || renamed.revision == descriptor.revision)
			throw "a package module override did not change enum target identity";
		registry.beginProgram("next-program");
		if (registry.nativeEnumValue("Payload") != null)
			throw "an old program retained its native enum representation";
		expectRejected(() -> OcamlNullableEnumCarrier.requireCurrent(carrierReference, context, registry),
			"a new program accepted the previous nullable enum carrier reference");
		Sys.println("REFLAXE_OCAML_ENUM_REPRESENTATION:PASS");
	}
	#end
}
