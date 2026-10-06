/**
 * Keep compiler-owned control bodies structural during source-shaped projection.
 * These lambdas transport loop and catch bodies; they are not ordinary callable values.
 * Remove only the derived ascription at each known body slot, retaining its annotation payload.
 */
function arguments(name:String, values:Array<HxExpr>):Array<HxExpr> {
	final projected = values.copy();
	switch (name) {
		case "__hxhx_while" | "__hxhx_do_while":
			if (projected.length >= 2) {
				projected[0] = body(projected[0]);
				projected[1] = body(projected[1]);
			}
		case "__hxhx_for_in" | "__hxhx_for_key_value" | "__hxhx_map_comprehension":
			if (projected.length >= 2)
				projected[1] = body(projected[1]);
		case "__hxhx_try":
			if (projected.length >= 2) {
				projected[0] = body(projected[0]);
				projected[1] = switch (projected[1]) {
					case EArrayDecl(entries): EArrayDecl([
							for (entry in entries)
								switch (entry) {
									case EArrayDecl([name, hint, handler]):
										EArrayDecl([name, hint, body(handler)]);
									case _:
										entry;
								}
						]);
					case other: other;
				};
			}
		case _:
	}
	return projected;
}

private function body(expression:HxExpr):HxExpr {
	return switch (expression) {
		case ECast(inner, _) if (inner.match(ELambda(_, _, _))): inner;
		case _: expression;
	};
}
