package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.OcamlDeclarationSignature;
import reflaxe.ocaml.lowered.OcamlInstanceMethodCatalog;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature.selectMethodSignature;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature.requireMethodNativeSignature;

/** One concrete slot whose checked native function implements the named contract. */
typedef OcamlMethodDispatchClassEntry = {
	final signature:OcamlMethodDispatchSignature;
	final nativeSignature:OcamlDeclarationSignature;
	final nativeModule:String;
	final implementationOwner:ClassType;
}

/** Complete registration facts for one constructor or empty-instance allocation. */
typedef OcamlMethodDispatchClassPlan = {
	final marker:OcamlClassIdentityMarkerPlan.OcamlClassIdentityMarkerDecision;
	final registryRevision:String;
	final recordSize:Int;
	final entries:Array<OcamlMethodDispatchClassEntry>;
}

/**
	Selects ordinary interface implementers without changing their concrete layout.

	Every ancestor must use the ordinary non-generic record emitter. The shared
	catalog supplies effective overrides; native types come from the existing
	declaration representation owner. Unsupported methods gain no registry entry.
	A later consumer must require its exact entry before output publication.
**/
function selectClassMethodEntries(owner:ClassType, catalog:OcamlInstanceMethodCatalog, project:Array<Type>->Type->Null<OcamlDeclarationSignature>,
		nativeModule:String):Array<OcamlMethodDispatchClassEntry> {
	var hasInterface = false;
	for (ancestor in catalog.chain) {
		if (ancestor.isInterface || ancestor.isExtern || ancestor.params.length != 0 || ancestor.meta.has(":native"))
			return [];
		switch (ancestor.kind) {
			case KNormal:
			case _:
				return [];
		}
		if (ancestor.interfaces.length > 0)
			hasInterface = true;
	}
	if (!hasInterface || catalog.chain.length == 0 || catalog.chain[catalog.chain.length - 1] != owner)
		return [];
	final entries:Array<OcamlMethodDispatchClassEntry> = [];
	for (name in catalog.order) {
		final declaration = catalog.declarations.get(name);
		if (declaration == null)
			throw "reflaxe.ocaml [ocaml-method-dispatch:missing-method]: concrete dispatch catalog lost " + name;
		final method = switch (TypeTools.follow(declaration.field.type)) {
			case TFun(arguments, result): {arguments: arguments, result: result};
			case _: continue;
		};
		final native = project(method.arguments.map(argument -> argument.t), method.result);
		if (native == null)
			continue;
		final signature = selectMethodSignature(declaration.field, native, nativeModule);
		if (signature != null)
			entries.push({
				signature: signature,
				nativeSignature: native,
				nativeModule: nativeModule,
				implementationOwner: declaration.owner
			});
	}
	entries.sort((left, right) -> left.signature.key < right.signature.key ? -1 : left.signature.key > right.signature.key ? 1 : 0);
	return entries;
}

/** Constructor and empty allocation share the same registry identity, but separate runtime uses. */
function sealClassMethodRegistration(marker:OcamlClassIdentityMarkerPlan.OcamlClassIdentityMarkerDecision, recordSize:Int,
		entries:Array<OcamlMethodDispatchClassEntry>):OcamlMethodDispatchClassPlan {
	OcamlClassIdentityMarkerPlan.requireDecision(marker);
	if (recordSize < 1 || entries.length == 0)
		throw "reflaxe.ocaml [ocaml-method-dispatch:invalid-registration]: class registration requires a native record and methods";
	final keys:Array<String> = [];
	for (entry in entries) {
		requireMethodNativeSignature(entry.signature, entry.nativeSignature, entry.nativeModule);
		if (entry.nativeSignature.parameters.length != entry.signature.parameterTypes.length || keys.contains(entry.signature.key))
			throw "reflaxe.ocaml [ocaml-method-dispatch:invalid-registration]: class method inventory is inconsistent";
		keys.push(entry.signature.key);
	}
	keys.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
	final revision = "sha256:" + Sha256.encode([
		"ocaml-method-dispatch-class-v1",
		marker.programRevision,
		marker.pipelineRevision,
		marker.runtimeClassName,
		Std.string(recordSize),
		keys.join("|"),
		entries.map(entry -> entry.implementationOwner.module
			+ ":"
			+ entry.implementationOwner.pack.concat([entry.implementationOwner.name]).join(".")
			+ ":"
			+ entry.signature.key)
			.join("|")].map(value -> value.length + ":" + value).join(""));
	return {
		marker: marker,
		registryRevision: revision,
		recordSize: recordSize,
		entries: entries.copy()
	};
}
#end
