package backend.cpp;

import backend.cpp.CppManagedClassStorage.CppManagedClassLayout;

/**
	Keep applied field types separate from the declaration's common-value layout.
	The shared class graph owns generic substitution. Every application retains
	its own field facts, while the descriptor authority verifies that applications
	share the same declaration offsets and public class identity. Declared field
	types remain available for native defaults: T is null even when applied to Int.
 */
class CppManagedClassLayouts {
	final program:CppTypedProgramProjection;
	final symbol:TypedBackendClassProjection->String;
	final publish:CppManagedClassLayout->Void;
	final applications = new haxe.ds.StringMap<CppManagedClassLayout>();

	public function new(program:CppTypedProgramProjection, symbol:TypedBackendClassProjection->String, publish:CppManagedClassLayout->Void) {
		this.program = program;
		this.symbol = symbol;
		this.publish = publish;
	}

	/** Only complete applied class types may select field storage; cached results remain revision checked. */
	public function requireType(type:TyType):CppManagedClassLayout {
		program.assertCurrent();
		CppManagedClosureAbi.assertComplete(type);
		if (type.getNominalIdentity() == null || TyTypeSubstitution.parameterIdentities(type).length != 0)
			throw "managed class storage requires an exact applied class";
		final key = type.getSemanticKey();
		final previous = applications.get(key);
		if (previous != null)
			return copy(previous);
		final owner = program.requireClass(program.requireClassIdentity(type.getNominalIdentity().getCanonicalName()));
		final facts = owner.requireSemanticFacts();
		for (metadata in HxClassDecl.getMetadata(owner.getDeclaration())) {
			final raw = StringTools.trim(metadata);
			final name = StringTools.startsWith(raw, "@:") ? raw.substr(2) : StringTools.startsWith(raw, ":") ? raw.substr(1) : raw;
			if (name == "generic" || StringTools.startsWith(name, "generic("))
				throw "managed specialized classes require their own runtime identity plan";
		}
		switch facts.getNominalKind() {
			case ClassInstance:
			case _:
				throw "managed instance storage cannot represent an enum or abstract";
		}
		if (facts.getIsExtern() || facts.getIsInterface())
			throw "managed class storage requires an explicit interface or native adapter plan";
		final selectedSymbol = symbol(owner);
		final lineage = program.getClassGraph().requireSpecializedLineageForType(type);
		final fields = lineage[0].fields.filter(field -> !field.isStatic && field.hasStorage);
		final declared = facts.copyFields().filter(field -> !field.isStatic && field.hasStorage);
		fields.sort((a, b) -> a.canonicalIdentity < b.canonicalIdentity ? -1 : a.canonicalIdentity > b.canonicalIdentity ? 1 : 0);
		declared.sort((a, b) -> a.canonicalIdentity < b.canonicalIdentity ? -1 : a.canonicalIdentity > b.canonicalIdentity ? 1 : 0);
		if (fields.length != declared.length)
			throw "applied class changed its declared field inventory";
		for (index in 0...fields.length) {
			CppManagedClosureAbi.assertComplete(fields[index].semanticType);
			if (fields[index].canonicalIdentity != declared[index].canonicalIdentity)
				throw "applied class changed its declared field order";
			if (fields[index].isInline)
				throw "managed class storage requires explicit inline field storage";
		}
		// The graph has already substituted every edge using its exact binder.
		final parent = lineage.length < 2 ? null : requireType(TyType.nominal(facts.getSuperType().getNominalIdentity(),
			[for (binding in lineage[1].bindings) binding.semanticType]));
		final layout:CppManagedClassLayout = {
			owner: owner,
			type: type,
			symbol: selectedSymbol,
			fields: parent == null ? fields : parent.fields.concat(fields),
			declaredFields: parent == null ? declared : parent.declaredFields.concat(declared),
			parent: parent == null ? null : parent.symbol
		};
		publish(layout);
		applications.set(key, layout);
		return copy(layout);
	}

	static function copy(layout:CppManagedClassLayout):CppManagedClassLayout
		return {
			owner: layout.owner,
			type: layout.type,
			symbol: layout.symbol,
			fields: layout.fields.copy(),
			declaredFields: layout.declaredFields.copy(),
			parent: layout.parent
		};
}
