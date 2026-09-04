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
		Sys.println("HXHX_OCAML_TARGET_DECLARATION_ADAPTER:PASS");
	}
}
