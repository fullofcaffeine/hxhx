package backend.source;

/**
	Mark C# field calls whose receiver is one exact Dynamic local.

	The temporary source-shaped body cannot recover local identity from rendered
	text. This lowering therefore consults the function's immutable local
	catalog before rendering and replaces only the selected calls with an
	explicit C# runtime-dispatch marker.
**/
class CsDynamicLocalCallLowering {
	public static inline function marker():String
		return "$hxhx:cs-dynamic-field-call";

	public static inline function isMarker(value:String):Bool
		return value == marker();

	public static function body(projection:TypedBackendFunctionProjection):Array<HxStmt> {
		if (projection == null)
			throw "C# Dynamic local-call lowering requires a typed function projection";
		final locals = projection.getLocalCatalog();
		return SourceFunctionBodyRewriter.body(HxFunctionDecl.getBody(projection.getDeclaration()), function(expression) {
			return switch (expression) {
				case ECall(EField(receiver, field), arguments) if (dependsOnExactDynamicLocal(receiver, locals)):
					ECall(EUnsupported(marker()), [receiver, EString(field), EArrayDecl(arguments)]);
				case _:
					expression;
			};
		});
	}

	static function dependsOnExactDynamicLocal(expression:HxExpr, locals:TypedBackendLocalCatalog):Bool {
		return switch (expression) {
			case EIdent(name): final local = locals.findByProjectedName(name); local != null && local.getBinding().getType().unwrapNull().isDynamic();
			case ECast(inner, _):
				dependsOnExactDynamicLocal(inner, locals);
			case EUntyped(inner) | EMacroExpr(inner, _):
				dependsOnExactDynamicLocal(inner, locals);
			case _:
				false;
		};
	}
}
