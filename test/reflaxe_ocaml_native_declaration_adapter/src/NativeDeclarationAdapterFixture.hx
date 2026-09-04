import backend.ocaml.HxhxOcamlTargetDeclarationAdapter;
import backend.ocaml.HxhxOcamlTargetLiteralAdapter;

/** Verifies that the native adapter compiles without a macro-host compatibility layer. **/
class NativeDeclarationAdapterFixture {
	static function main():Void {
		final owner = new TyNominalTypeId("unit.NativeSample");
		final fields = new haxe.ds.StringMap<TyFieldInfo>();
		fields.set("count", new TyFieldInfo(owner, "unit.NativeSample", "count", TyType.fromHintText("Int"), false, true, false, false, true));
		final info = new TyClassInfo(owner, "NativeSample", "unit.NativeSample", fields, new haxe.ds.StringMap(), new haxe.ds.StringMap(),
			new haxe.ds.StringMap(), new haxe.ds.StringMap(), new haxe.ds.StringMap(), [], Public, false);
		final request = HxhxOcamlTargetDeclarationAdapter.fromClassFacts("native-fixture-program", [new TypedBackendClassSemanticFacts(info, null)]);
		final classes = request.copyClasses();
		if (classes.length != 1 || classes[0].copyFields().length != 1 || classes[0].copyFields()[0].typeDisplay != "Int")
			throw "native semantic field was not copied into target-owned facts";
		final nativeInt = HxhxOcamlTargetLiteralAdapter.fromExpression(TypedExpr.intLiteral(7, TyType.fromHintText("Int"), HxPos.unknown()));
		if (nativeInt == null || nativeInt.getCanonicalIdentity() != LiteralIdentityMacro.stockInt())
			throw "stock Haxe and native hxhx produced different integer literal facts";
		if (HxhxOcamlTargetLiteralAdapter.fromExpression(TypedExpr.floatLiteral(1.5, TyType.fromHintText("Float"), HxPos.unknown())) != null)
			throw "native adapter admitted a float before the numeric review contract";
		Sys.println("HXHX_OCAML_TARGET_DECLARATION_ADAPTER:PASS");
	}
}
