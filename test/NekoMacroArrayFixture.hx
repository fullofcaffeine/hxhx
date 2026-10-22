/** Native adapter tests use a real Array provider; end-to-end fixtures separately prove hxhx's provider. */
function prepare(root:String):backend.vm.NekoArrayProvider.NekoArrayFactory {
	final output = root + "/arrays.n";
	final process = new sys.io.Process("haxe", [
		"-cp",
		"test/fixtures/neko_macro_array_provider",
		"-main",
		"ArrayProvider",
		"-neko",
		output
	]);
	final stdout = process.stdout.readAll().toString();
	final stderr = process.stderr.readAll().toString();
	final code = process.exitCode();
	process.close();
	if (code != 0)
		throw "Neko quotation Array provider failed: " + stdout + stderr;
	return {
		reference: "$loader.loadmodule(" + haxe.Json.stringify(root + "/arrays") + ", $loader).wrap",
		storage: "__fixture_quotation_array"
	};
}
