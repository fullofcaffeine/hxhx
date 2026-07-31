package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr;
import haxe.macro.Expr.Position;
import haxe.macro.Type.MetaAccess;
#if macro
import haxe.macro.Context;
#end

using StringTools;

/**
	Recovers the canonical Haxe declaration name retained by the typer.

	`@:native` may replace a source class or field name with one target symbol.
	Haxe keeps the original declaration name in `@:realPath`; lowering uses that
	typed fact when different source declarations share the same native symbol.
**/
class OcamlTypedDeclarationIdentity {
	public static inline final REAL_PATH_METADATA = ":realPath";

	/**
		Returns the canonical source name, or `fallback` for declarations that
		were not renamed by the typer.

		Malformed or repeated identity metadata fails before target syntax is
		produced because choosing a carrier from an ambiguous identity is unsafe.
	**/
	public static function canonicalSourceName(meta:MetaAccess, fallback:String, owner:String):String {
		var sourceName:Null<String> = null;
		for (entry in meta.get()) {
			if (entry.name != REAL_PATH_METADATA)
				continue;
			if (entry.params == null || entry.params.length != 1)
				fail('$REAL_PATH_METADATA on $owner requires exactly one constant source name.', entry.pos);
			final candidate = switch (entry.params[0].expr) {
				case EConst(CString(value)): value.trim();
				case _: fail('$REAL_PATH_METADATA on $owner requires a constant source name.', entry.params[0].pos);
			};
			if (candidate.length == 0)
				fail('$REAL_PATH_METADATA on $owner must not use an empty source name.', entry.pos);
			if (sourceName != null)
				fail('$REAL_PATH_METADATA repeats on the same $owner.', entry.pos);
			sourceName = candidate;
		}
		return sourceName ?? fallback;
	}

	static function fail(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [typed-declaration-identity]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}
}
#end
