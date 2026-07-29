package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr;
import haxe.macro.Expr.Position;
#if macro
import haxe.macro.Context;
#end
import haxe.macro.Type;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlTypedDeclarationIdentity;

using StringTools;

/**
	Records runtime capabilities explicitly declared by typed OCaml externs.

	@:ocamlRuntime("capability") states why a checked reflaxe.ocaml runtime
	module is needed. It does not select arbitrary native libraries: the runtime
	ledger owns the closed capability-to-module mapping and verifies the resolved
	@:native symbol before accepting the declaration.
**/
class OcamlNativeRuntimeBoundary {
	public static inline final METADATA = ":ocamlRuntime";

	/**
		Reports whether a native extern callable declares a checked runtime
		capability on either its class or field.

		This check keeps the generic native-constructor path closed: an arbitrary
		`@:native` constructor is not enough to opt into a reflaxe.ocaml runtime
		module.
	**/
	public static function hasDeclaredRuntimeCapability(classType:ClassType, field:ClassField):Bool {
		return classType.meta.has(METADATA) || field.meta.has(METADATA);
	}

	/**
		Records class- and field-level declarations for one emitted extern
		callable, including constructors and static functions. Repeated uses of
		the same declaration produce the same immutable requirement.
	**/
	public static function recordUsedExternCallable(context:CompilationContext, classType:ClassType, field:ClassField, nativeSymbol:String):Void {
		final capabilities = new Array<String>();
		final seen:Map<String, Bool> = [];
		collectCapabilities(classType.meta, "extern class", capabilities, seen);
		collectCapabilities(field.meta, "extern field", capabilities, seen);
		capabilities.sort(compareStrings);
		if (capabilities.length == 0)
			return;

		final rewrittenTypePath = (classType.pack ?? []).concat([classType.name]).join(".");
		final sourceTypePath = OcamlTypedDeclarationIdentity.canonicalSourceName(classType.meta, rewrittenTypePath, "an extern class");
		final sourceFieldName = OcamlTypedDeclarationIdentity.canonicalSourceName(field.meta, field.name, "an extern field");
		final boundaryId = classType.module + "::" + sourceTypePath + "." + sourceFieldName;
		for (capability in capabilities) {
			try {
				context.recordNativeRuntimeBoundary(capability, boundaryId, OcamlLoweredOrigin.sourceSpan(field.pos), nativeSymbol);
			} catch (error:Dynamic) {
				fail(Std.string(error), field.pos);
			}
		}
	}

	static function collectCapabilities(meta:MetaAccess, owner:String, out:Array<String>, seen:Map<String, Bool>):Void {
		for (entry in meta.get()) {
			if (entry.name != METADATA)
				continue;
			if (entry.params == null || entry.params.length != 1)
				fail('$METADATA on an $owner requires exactly one constant capability string.', entry.pos);
			final capability = switch (entry.params[0].expr) {
				case EConst(CString(value)): value.trim();
				case _: fail('$METADATA on an $owner requires a constant capability string.', entry.params[0].pos);
			};
			if (capability.length == 0)
				fail('$METADATA on an $owner must not use an empty capability.', entry.pos);
			if (seen.exists(capability))
				fail('$METADATA repeats capability "$capability" on the same native extern boundary.', entry.pos);
			seen.set(capability, true);
			out.push(capability);
		}
	}

	static function fail(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-runtime:native-boundary]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
