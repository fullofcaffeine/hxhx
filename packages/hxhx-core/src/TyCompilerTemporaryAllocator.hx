/**
	Allocates deterministic typed bindings for locals introduced by one pass.

	An allocator belongs to exactly one typed function and one versioned lowering
	pass. Its ordinal restarts at the function boundary, so adding or reordering
	an unrelated function cannot change another function's temporary identities.
	The generated name remains a backend-facing diagnostic/source-projection fact;
	the `TyLocalId` is the semantic declaration identity.
**/
class TyCompilerTemporaryAllocator {
	final functionIdentity:String;
	final passIdentity:String;
	final generatedNamePrefix:String;
	var nextOrdinal:Int;

	public function new(functionIdentity:String, passIdentity:String, generatedNamePrefix:String) {
		if (functionIdentity == null || functionIdentity.length == 0)
			throw "compiler temporary allocator requires a function owner";
		if (passIdentity == null || passIdentity.length == 0)
			throw "compiler temporary allocator requires a lowering pass";
		if (generatedNamePrefix == null || generatedNamePrefix.length == 0)
			throw "compiler temporary allocator requires a generated-name prefix";
		this.functionIdentity = functionIdentity;
		this.passIdentity = passIdentity;
		this.generatedNamePrefix = generatedNamePrefix;
		nextOrdinal = 0;
	}

	/** Allocate the next immutable declaration binding in deterministic pass order. **/
	public function allocate(role:String, type:TyType):TyLocalBinding {
		if (type == null)
			throw "compiler temporary allocator requires a semantic type";
		final ordinal = nextOrdinal++;
		final cleanRole = role == null || role.length == 0 ? "value" : role;
		final generatedName = generatedNamePrefix + cleanRole + "_" + ordinal;
		return new TyLocalBinding(TyLocalId.forCompilerTemporary(functionIdentity, passIdentity, ordinal, generatedName), generatedName, type,
			CompilerTemporary);
	}

	/** Freshen an authored local or callable parameter without changing its semantic declaration role. */
	public function copy(source:TyLocalBinding, type:TyType):TyLocalBinding {
		final ordinal = nextOrdinal++;
		final name = generatedNamePrefix + "copied_" + ordinal;
		return new TyLocalBinding(TyLocalId.forLoweredDeclaration(functionIdentity, passIdentity, ordinal, name, source.getKind()), name, type,
			source.getKind());
	}
}
