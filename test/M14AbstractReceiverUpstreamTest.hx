import sys.io.File;
import sys.FileSystem;

/** Pins upstream storage-access behavior before shared inline-call lowering is implemented. */
class M14AbstractReceiverUpstreamTest {
	public static function main():Void {
		final fixture = "test/abstract_receiver_writeback";
		final root = ".tmp/abstract_receiver_upstream_" + Date.now().getTime();
		FileSystem.createDirectory(root);
		for (target in ["neko", "js"]) {
			final output = root + "/main." + (target == "neko" ? "n" : "js");
			@:privateAccess M14JsRuntimeTypeOperandsTest.run("haxe", ["-cp", fixture, "-main", "Main", "-" + target, output]);
			final actual = @:privateAccess M14JsRuntimeTypeOperandsTest.run(target == "neko" ? "neko" : "node", [output]);
			File.saveContent(root + "/" + target + ".stdout", actual);
			if (actual != File.getContent(fixture + "/expected." + target + ".stdout"))
				throw "upstream inline abstract storage contract changed for " + target + ": " + root;
			Sys.println("ABSTRACT_RECEIVER_UPSTREAM_CONTRACT:PASS target=" + target);
		}
	}
}
