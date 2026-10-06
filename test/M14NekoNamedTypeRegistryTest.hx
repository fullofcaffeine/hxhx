import backend.vm.NekoNamedTypeRegistry.render;
import backend.vm.NekoNamedTypeRegistry.NekoNamedType;

/** Exercises the bootstrap tree renderer independently of unrelated standard-library startup failures. */
class M14NekoNamedTypeRegistryTest {
	static function reject(entries:Array<NekoNamedType>, fragment:String):Void {
		final output = new Array<String>();
		var diagnostic = "";
		try {
			render(output, entries, "symbols", "named");
		} catch (error:String) {
			diagnostic = error;
		}
		if (diagnostic.indexOf(fragment) < 0 || output.length != 0)
			throw "invalid named registry was not rejected before publication: " + diagnostic;
	}

	static function main():Void {
		final entries:Array<NekoNamedType> = [
			{identity: "nominal:demo.Item.Nested", name: "demo.Item.Nested"},
			{identity: "nominal:neko.Boot", name: "neko.Boot"},
			{identity: "core:Int", name: "Int"},
			{identity: "nominal:demo.Item", name: "demo.Item"}
		];
		final rendered = new Array<String>();
		render(rendered, entries, "symbols", "named");
		final reordered = new Array<String>();
		final reversed = entries.copy();
		reversed.reverse();
		render(reordered, reversed, "symbols", "named");
		if (rendered.join("\n") != reordered.join("\n"))
			throw "named registry depends on descriptor input order";
		reject([{identity: "first", name: "same"}, {identity: "second", name: "same"}], "conflicting public names");
		reject([{identity: "bad", name: "a..b"}], "empty namespace component");
		final source = ["var symbols = $new(null);", "symbols.__hxhx_types = $new(null);"];
		for (entry in entries)
			source.push("$objset(symbols.__hxhx_types, $hash(" + haxe.Json.stringify(entry.identity) + "), $new(null));");
		for (line in rendered)
			source.push(line);
		source.push('var original = $$objget(symbols.__hxhx_types,$$hash("core:Int"));');
		source.push('if(symbols.named.Int != original) $$throw("core entry lost identity");');
		source.push('if(symbols.named.demo.Item != $$objget(symbols.__hxhx_types,$$hash("nominal:demo.Item"))) $$throw("class namespace lost identity");');
		source.push('if(symbols.named.demo.Item.Nested != $$objget(symbols.__hxhx_types,$$hash("nominal:demo.Item.Nested"))) $$throw("nested entry lost identity");');
		source.push('if(symbols.named.neko.Boot.__classes != symbols.named) $$throw("Boot did not receive the shared tree");');
		source.push('var binding = $$array(original); binding[0] = $$new(null);');
		source.push('if(symbols.named.Int == binding[0] || symbols.named.Int != original) $$throw("registry followed a mutable binding");');
		source.push('$$print("named-registry-ok\\n");');
		final root = ".tmp/neko_named_type_registry_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/main.neko", source.join("\n"));
		@:privateAccess M14JsRuntimeTypeOperandsTest.run("nekoc", [root + "/main.neko"]);
		if (@:privateAccess M14JsRuntimeTypeOperandsTest.run("neko", [root + "/main.n"]) != "named-registry-ok\n")
			throw "native named registry observer differs";
		Sys.println("NEKO_NAMED_TYPE_REGISTRY:PASS");
	}
}
