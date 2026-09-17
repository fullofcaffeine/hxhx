/** Checks projection object identity without loading the full compiler pipeline. */
class M14RuntimeTypeOccurrenceIdentityTest {
	static function main():Void {
		final target = new TypedRuntimeTypeTarget(Nominal(new TyNominalTypeId("sample.Parent")));
		final occurrence = new TypedBackendRuntimeTypeOccurrence("owner", "revision", target);
		final catalog = new TypedBackendRuntimeTypeCatalog("owner", "revision", [occurrence]);
		if (catalog.require(occurrence.getExpression(), "owner", "revision") != occurrence)
			throw "owning occurrence was lost";
		final copy:HxExpr = ECall(EIdent(TypedRuntimeTypeSource.VALUE), []);
		var rejected = false;
		try {
			catalog.require(copy, "owner", "revision");
		} catch (error:Dynamic) {
			// This boundary observes the catalog's raw String diagnostic. Validate it
			// before narrowing so an unrelated exception cannot pass this identity test.
			if (!Std.isOfType(error, String))
				throw error;
			final message:String = cast error;
			if (message != "runtime type operand is not an exact occurrence in this executable projection")
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "structurally equal marker bypassed occurrence identity";
		Sys.println("RUNTIME_TYPE_OCCURRENCE_IDENTITY:PASS");
	}
}
