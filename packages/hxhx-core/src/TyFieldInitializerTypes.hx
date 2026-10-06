private typedef CheckedFieldType = {
	final source:HxFieldDecl;
	final fingerprint:String;
	final type:TyType;
}

/**
	Request-owned initializer evidence for fields without written types.
	Declarations remain immutable. The shared typer supplies declaring-module
	computation, and unresolved cycles cannot authorize a completed field type.
 */
class TyFieldInitializerTypes {
	final sources = new haxe.ds.ObjectMap<TyFieldInfo, HxFieldDecl>();
	final checked = new haxe.ds.ObjectMap<TyFieldInfo, CheckedFieldType>();
	final active = new haxe.ds.ObjectMap<TyFieldInfo, Bool>();
	var infer:Null<(TyFieldInfo, HxFieldDecl) -> TyType>;

	public function new() {}

	/** Register the exact source association when the index publishes the field. */
	public function register(field:TyFieldInfo, source:HxFieldDecl):Void {
		sources.set(field, source);
	}

	public function configure(infer:(TyFieldInfo, HxFieldDecl) -> TyType):Void {
		this.infer = infer;
	}

	/** Freeze checked results while retaining source and exact declaration ownership. */
	public function publish(owner:TyNominalInfo):TypedDeclaredFieldTypes {
		final entries = [];
		for (field in owner.getFieldInfos()) {
			final source = sources.get(field);
			final initializer = source == null ? null : HxFieldDecl.getInit(source);
			if (field.getType().isUnknown() && initializer != null)
				entries.push({
					declaration: field,
					source: source,
					fingerprint: TypedBodyFingerprint.exactExpression(initializer),
					type: result(field)
				});
		}
		return new TypedDeclaredFieldTypes(owner, entries);
	}

	public function result(field:TyFieldInfo):TyType {
		if (!field.getType().isUnknown())
			return field.getType();
		final source = sources.get(field);
		final initializer = source == null ? null : HxFieldDecl.getInit(source);
		if (initializer == null || infer == null)
			return field.getType();
		final fingerprint = TypedBodyFingerprint.exactExpression(initializer);
		final previous = checked.get(field);
		if (previous != null) {
			if (previous.source != source || previous.fingerprint != fingerprint)
				throw 'field initializer type belongs to changed source';
			return previous.type;
		}
		if (active.exists(field)) {
			// Every active consumer depends on this unresolved initialization cycle.
			for (consumer in active.keys())
				active.set(consumer, true);
			return TyType.unknown();
		}
		active.set(field, false);
		final selected = try {
			infer(field, source);
		} catch (error:haxe.Exception) {
			active.remove(field);
			throw error;
		}
		final cyclic = active.get(field);
		active.remove(field);
		if (cyclic
			|| selected.hasUnknownComponent()
			|| selected.isNullLiteral()
			|| selected.isVoid()
			|| selected.isNoNormalCompletion())
			return TyType.unknown();
		checked.set(field, {source: source, fingerprint: fingerprint, type: selected});
		return selected;
	}
}
