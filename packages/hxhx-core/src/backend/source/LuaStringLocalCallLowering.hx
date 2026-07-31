package backend.source;

/**
	Lower Lua String calls that depend on an exact typed value.

	The shared source-shaped renderer cannot recover a local or bare field's
	semantic type from its transport name. This lowering therefore runs before
	text rendering, while each function is still paired with its exact local and
	field-read catalogs. Literal and explicit typed-intrinsic handling remains in
	the Lua renderer.
**/
class LuaStringLocalCallLowering {
	/**
		Return one structurally rewritten function body.

		Only supported String methods whose receiver depends on an exact String
		local or exact static field become explicit Lua runtime-helper calls. All
		other nodes preserve their source-shaped structure.
	**/
	public static function body(projection:TypedBackendFunctionProjection):Array<HxStmt> {
		if (projection == null)
			throw "Lua String local lowering requires a typed function projection";
		final locals = projection.getLocalCatalog();
		final fields = projection.getFieldReadCatalog();
		return SourceFunctionBodyRewriter.body(HxFunctionDecl.getBody(projection.getDeclaration()), function(expression) {
			return switch (expression) {
				case ECall(EField(receiver, field), arguments): final helper = stringHelper(field,
						arguments.length); helper != null && dependsOnExactStringValue(receiver, locals,
						fields) ? ECall(EIdent(helper), [receiver].concat(arguments)) : expression;
				case EBinop("+", left, right) if (dependsOnExactStringValue(left, locals, fields)
					|| dependsOnExactStringValue(right, locals, fields)):
					ECall(EIdent("__hxhx_lua_string_concat"), [left, right]);
				case _:
					expression;
			};
		});
	}

	static function stringHelper(field:String, argumentCount:Int):Null<String> {
		return switch (field) {
			case "indexOf" if (argumentCount == 1 || argumentCount == 2): "__hxhx_string_index_of";
			case "contains" if (argumentCount == 1): "__hxhx_string_contains";
			case "substr" if (argumentCount == 1 || argumentCount == 2): "__hxhx_string_substr";
			case "startsWith" if (argumentCount == 1): "__hxhx_string_starts_with";
			case "toUpperCase" if (argumentCount == 0): "__hxhx_string_to_upper_case";
			case "toLowerCase" if (argumentCount == 0): "__hxhx_string_to_lower_case";
			case _: null;
		};
	}

	static function dependsOnExactStringValue(expression:HxExpr, locals:TypedBackendLocalCatalog, fields:TypedBackendFieldReadCatalog):Bool {
		return switch (expression) {
			case EIdent(name):
				final local = locals.findByProjectedName(name);
				if (local != null) {
					isStringType(local.getBinding().getType());
				} else {
					final field = fields.findByProjectedName(name);
					field != null && field.getField().getIsStatic() && isStringType(field.getField().getType())
					;
				}
			case EBinop("+", left, right): dependsOnExactStringValue(left, locals, fields) || dependsOnExactStringValue(right, locals, fields);
			case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				dependsOnExactStringValue(inner, locals, fields);
			case ECall(EIdent("__hxhx_lua_string_concat"), _):
				true;
			case _:
				false;
		};
	}

	static function isStringType(type:TyType):Bool
		return type != null && type.unwrapNull().getSemanticKey() == "primitive:String";
}
