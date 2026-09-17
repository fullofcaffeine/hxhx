/** The value view that an admitted typed handler receives from its native carrier. */
enum TypedCatchView {
	Carrier;
	BaseException;
	ExceptionSubtype;
	OrdinaryValue;
}

/**
	Exact implicit runtime uses selected while the declaration index is still open.

	A catch can use standard-library declarations even when its local is never
	read. These facts keep those uses visible to dependency tracking and later
	backend preparation. They do not emit code or choose executable reachability.
	Only the Neko typing policy currently requests this conversion contract.
**/
class TypedCatchUse {
	public final binding:TyLocalBinding;
	public final view:TypedCatchView;
	public final target:Null<TypedRuntimeTypeTarget>;
	public final conversion:Null<TyDeclarationInfo>;
	public final payload:Null<TyFieldInfo>;

	function new(binding:TyLocalBinding, view:TypedCatchView, target:Null<TypedRuntimeTypeTarget>, conversion:Null<TyDeclarationInfo>,
			payload:Null<TyFieldInfo>) {
		this.binding = binding;
		this.view = view;
		this.target = target;
		this.conversion = conversion;
		this.payload = payload;
	}

	/** Select real providers through the request's normal, target-aware module loader. */
	public static function resolve(binding:TyLocalBinding, context:TyperContext):TypedCatchUse {
		if (binding == null || !binding.getKind().match(CatchVariable))
			throw "implicit catch use requires an exact catch binding";
		final type = binding.getType();
		if (type.isDynamic())
			return new TypedCatchUse(binding, Carrier, null, null, null);
		final identity = type.getNominalIdentity();
		if (identity != null && identity.getCanonicalName() == "haxe.Exception") {
			final provider = requireProvider(context, "haxe.Exception");
			final candidates = provider.staticMethodCandidates("caught");
			if (candidates.length != 1)
				throw "implicit catch conversion requires one exact haxe.Exception.caught declaration";
			final declaration = provider.declarationForSignature(candidates[0]);
			final arguments = candidates[0].getArgs();
			if (declaration == null
				|| arguments.length != 1
				|| arguments[0].getSemanticKey() != "nominal:Any"
				|| candidates[0].getReturnType().getSemanticKey() != "nominal:haxe.Exception")
				throw "implicit catch conversion has an unsupported signature: ("
					+ [for (arg in arguments) arg.getSemanticKey()].join(",") + ")->" + candidates[0].getReturnType().getSemanticKey();
			return new TypedCatchUse(binding, BaseException, null, declaration, null);
		}
		final target = switch (type.getSemanticKey()) {
			case "primitive:Int" | "nominal:StdTypes.Int": new TypedRuntimeTypeTarget(IntCore);
			case "primitive:Float" | "nominal:StdTypes.Float": new TypedRuntimeTypeTarget(FloatCore);
			case "primitive:Bool" | "nominal:StdTypes.Bool": new TypedRuntimeTypeTarget(BoolCore);
			case "primitive:String" | "nominal:String": new TypedRuntimeTypeTarget(StringCore);
			case _:
				if (identity == null)
					throw "unsupported implicit catch type: " + type.getSemanticKey();
				final selected = requireProvider(context, identity.getCanonicalName());
				if (!Std.isOfType(selected, TyClassInfo) || selected.getIsEnum())
					throw "unsupported implicit catch target: " + type.getSemanticKey();
				identity.getCanonicalName() == "Array" ? new TypedRuntimeTypeTarget(ArrayCore) : new TypedRuntimeTypeTarget(Nominal(identity));
		};
		if (target.getKind().match(Nominal(_))) {
			final selected = requireProvider(context, identity.getCanonicalName());
			final exception = requireProvider(context, "haxe.Exception");
			if (context.classIsOrExtends(selected, exception, true))
				return new TypedCatchUse(binding, ExceptionSubtype, target, null, null);
		}
		final wrapper = requireProvider(context, "haxe.ValueException");
		final payload = wrapper.fieldInfo("value");
		// The selected standard field uses the Any carrier abstract. Retain its
		// exact declaration rather than replacing it with a guessed Dynamic field.
		if (payload == null
			|| payload.getIsStatic()
			|| payload.getType().getSemanticKey() != "nominal:Any"
			|| payload.getPropertyGet() != "default"
			|| payload.getOwner().getCanonicalName() != "haxe.ValueException")
			throw "implicit catch payload requires the real haxe.ValueException.value field";
		return new TypedCatchUse(binding, OrdinaryValue, target, null, payload);
	}

	static function requireProvider(context:TyperContext, identity:String):TyNominalInfo {
		final provider = context.resolveType(identity);
		if (provider == null || provider.getIdentity().getCanonicalName() != identity)
			throw "implicit catch provider is unavailable: " + identity;
		return provider;
	}

	/** Include implicit-use identity in semantic revisions, independent of emitted names. */
	public function getCanonicalIdentity():String {
		final kind = switch (view) {
			case Carrier: "carrier";
			case BaseException: "base-exception";
			case ExceptionSubtype: "exception-subtype";
			case OrdinaryValue: "ordinary-value";
		};
		return CompilerCacheIdentity.encode([
			"typed-catch-use-v1",
			binding.getCanonicalIdentity(),
			kind,
			target == null ? null : target.getSemanticKey(),
			conversion == null ? null : conversion.getIdentity().getCanonicalKey(),
			payload == null ? null : payload.getCanonicalKey(),
			payload == null ? null : payload.getType().getSemanticKey()
		]);
	}
}
