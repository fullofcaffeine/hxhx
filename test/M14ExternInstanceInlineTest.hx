import sys.io.File;

/** Real target execution and declaration checks guard required instance expansion. */
class M14ExternInstanceInlineTest {
	static function main():Void {
		final source = File.getContent("test/fixtures/extern_instance_inline/Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		var externMethods = 0;
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions()) {
				final declaration = fn.getDeclaration();
				if (["read", "copy", "optional", "defaulted", "skip", "promote"].contains(declaration.getSignature().getName())) {
					if (!declaration.getIsExtern() || !declaration.getIsInline())
						throw "member extern inline authority disappeared";
					externMethods++;
				} else if (declaration.getIsExtern())
					throw "extern modifier leaked to another member";
			}
		if (externMethods != 6)
			throw "extern declaration inventory differs";
		final scanned = ParserStageScanHelpers.scanModuleLocalHelperAbstracts('abstract Wrapped(Int) { public extern inline function read():Int return this; public function ordinary():Int return this; }',
			null);
		if (scanned.length != 1)
			throw "abstract scanner inventory differs";
		for (fn in HxClassDecl.getFunctions(scanned[0]))
			if ((HxFunctionDecl.getMetadata(fn).indexOf("extern") >= 0) != (HxFunctionDecl.getName(fn) == "read"))
				throw "scanner lost or leaked member extern authority";
		final lowered = TypedRequiredInlineLowering.lowerClasses(typed.getTypedClasses(), index);
		var ordinaryCalls = 0;
		var checkedConstruction = false;
		function expression(value:TypedExpr):Void {
			final application = value.getConstructorApplication();
			if (!checkedConstruction
				&& value.getTag() == NewValue
				&& application != null
				&& value.getExpressions().length == 1
				&& application.getConstructedType().getTypeArguments().length == 1
				&& application.getConstructedType().getTypeArguments()[0].getSemanticKey() == TyType.fromHintText("String").getSemanticKey()) {
				application.assertResult(value.getType());
				final wrong = [TypedExpr.intLiteral(42, TyType.fromHintText("Int"), value.getPosition())];
				var rejected = false;
				try {
					application.specialize(index, new haxe.ds.StringMap<TyType>(), value.getExpressions(), wrong);
				} catch (_:haxe.Exception) {
					rejected = true;
				}
				if (!rejected)
					throw "constructor specialization admitted changed operand types";
				checkedConstruction = true;
			}
			if (value.getTag() == Call && value.getDeclaration() != null) {
				final name = value.getDeclaration().getSignature().getName();
				if (["read", "copy", "optional", "defaulted", "skip", "promote"].contains(name))
					throw "required call escaped inline expansion";
				if (name == "ordinary")
					ordinaryCalls++;
			}
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in lowered)
			for (fn in owner.getFunctions())
				for (body in fn.getBody().getStatements())
					statement(body);
		if (ordinaryCalls != 1)
			throw "ordinary method call was replaced";
		if (!checkedConstruction)
			throw "specialized constructor negative was not exercised";
		@:privateAccess M14MultiTypeRuntimeTest.run("extern_instance", source);
		Sys.println("EXTERN_INSTANCE_INLINE:PASS");
	}
}
