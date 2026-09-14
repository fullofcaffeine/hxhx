package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.OcamlNameTools;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;

/**
	Names one ordinary enum's native variant without proving any value producer.

	The source module remains distinct from the semantic type and target module:
	secondary Haxe enums share a source file, and packaging can rename its OCaml
	module. This immutable descriptor contains no request-local macro objects.
**/
typedef OcamlNativeEnumDescriptor = {
	final semanticTypeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final targetModuleName:String;
	final targetTypeName:String;
	final revision:String;
}

/**
	Selects the native variant family for closed ordinary Haxe enums.

	Selection describes a target type only. A constructor, local, or call result
	still needs separate body-bound evidence before identity conversion is safe.
	Nullable, generic, extern, native-renamed, and OCaml interop enum types are
	out of scope; following abstracts here would erase that distinction.
**/
class OcamlNativeEnumRepresentation {
	public static inline final MODEL_REVISION = "ocaml-native-enum-variant-v1";

	/**
		Identifies a constructor at this typed occurrence, not an enum annotation.
		The enclosing result planner must bind this fact to its final body revision.
		Locals, calls to ordinary functions, and casts need their own producer proof.
	**/
	public static function selectDirectConstructor(expression:TypedExpr, context:CompilationContext):Null<OcamlNativeEnumDescriptor> {
		final descriptor = select(expression.t, context);
		if (descriptor == null)
			return null;
		final value = unwrapSourceWrappers(expression);
		final declaration = switch (value.expr) {
			case TField(_, FEnum(reference, _)): reference.get();
			case TCall(callee, _):
				switch (unwrapSourceWrappers(callee).expr) {
					case TField(_, FEnum(reference, _)): reference.get();
					case _: null;
				}
			case _: null;
		};
		return declaration != null
			&& declaration.module == descriptor.sourceModuleId
			&& declaration.name == descriptor.sourceTypeName ? descriptor : null;
	}

	static function unwrapSourceWrappers(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TParenthesis(child), TMeta(_, child): unwrapSourceWrappers(child);
			case _: expression;
		};
	}

	/** Materializes a registry-validated variant type relative to its current OCaml module. */
	public static function typeExpr(decision:OcamlRepresentationDecision, currentTargetModuleName:String):OcamlTypeExpr {
		if (decision.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectNativeEnumCarrier
			|| decision.nominalTargetModuleName == null
			|| decision.nominalTargetTypeName == null
			|| decision.nominalLayoutRevision == null
			|| currentTargetModuleName.length == 0)
			throw "reflaxe.ocaml [ocaml-native-enum:invalid-materialization]: expected a complete native variant decision and current module";
		return
			OcamlTypeExpr.TIdent(decision.nominalTargetModuleName == currentTargetModuleName ? decision.nominalTargetTypeName : decision.nominalTargetModuleName
			+ "."
			+ decision.nominalTargetTypeName);
	}

	/** Resolves transparent compiler references while preserving abstract boundaries. */
	public static function select(type:Type, context:CompilationContext):Null<OcamlNativeEnumDescriptor> {
		var current = type;
		for (_ in 0...32) {
			switch (current) {
				case TLazy(resolve):
					current = resolve();
				case TMono(reference):
					final resolved = reference.get();
					if (resolved == null)
						return null;
					current = resolved;
				case TEnum(reference, parameters):
					final declaration = reference.get();
					if (parameters.length != 0
						|| declaration.params.length != 0
						|| declaration.isExtern
						|| declaration.meta.has(":native")
						|| (declaration.pack.length > 0 && declaration.pack[0] == "ocaml"))
						return null;
					final descriptor:OcamlNativeEnumDescriptor = {
						semanticTypeId: declaration.pack.concat([declaration.name]).join("."),
						sourceModuleId: declaration.module,
						sourceTypeName: declaration.name,
						targetModuleName: context.ocamlModuleNameForModuleId(declaration.module),
						targetTypeName: OcamlNameTools.enumTypeName(declaration.name),
						revision: ""
					};
					return withRevision(descriptor);
				case _:
					return null;
			}
		}
		return null;
	}

	/** Rejects edited or incomplete descriptors before a program registry accepts them. */
	public static function validate(descriptor:OcamlNativeEnumDescriptor):Void {
		if (descriptor == null
			|| descriptor.semanticTypeId.length == 0
			|| descriptor.sourceModuleId.length == 0
			|| descriptor.sourceTypeName.length == 0
			|| descriptor.targetModuleName.length == 0
			|| descriptor.targetTypeName != OcamlNameTools.enumTypeName(descriptor.sourceTypeName)
			|| descriptor.revision != revision(descriptor))
			throw "reflaxe.ocaml [ocaml-native-enum:invalid-descriptor]: native enum identity or target naming facts changed";
	}

	static function withRevision(descriptor:OcamlNativeEnumDescriptor):OcamlNativeEnumDescriptor {
		return {
			semanticTypeId: descriptor.semanticTypeId,
			sourceModuleId: descriptor.sourceModuleId,
			sourceTypeName: descriptor.sourceTypeName,
			targetModuleName: descriptor.targetModuleName,
			targetTypeName: descriptor.targetTypeName,
			revision: revision(descriptor)
		};
	}

	static function revision(descriptor:OcamlNativeEnumDescriptor):String {
		final fields = [
			MODEL_REVISION,
			descriptor.semanticTypeId,
			descriptor.sourceModuleId,
			descriptor.sourceTypeName,
			descriptor.targetModuleName,
			descriptor.targetTypeName
		];
		return "sha256:" + Sha256.encode([for (field in fields) field.length + ":" + field].join(""));
	}
}
#end
