import backend.vm.NekoTargetCore;

/** Generated constructor guards must count both active payload containers before reading nested arguments. */
class M14NekoEnumPayloadCountTest {
	public static function run():Void {
		final root = ".tmp/neko-enum-payload-count";
		sys.FileSystem.createDirectory(root);
		final factory = NekoMacroArrayFixture.prepare(root);
		final pattern = HxSwitchPattern.PEnumExtract("Pair", [PInt(4), PEnumExtract("Nested", [PInt(7)])]);
		final lowered = @:privateAccess NekoTargetCore.lowerNekoSwitchPattern(null, pattern, "value");
		final source = sys.io.File.getContent("test/neko_enum_payload_count/Observer.neko");
		sys.io.File.saveContent(root + "/main.neko",
			StringTools.replace(StringTools.replace(source, "@@ARRAY_FACTORY@@", factory.reference), "@@CONDITION@@", lowered.cond));
		M14Stage3RuntimeFixture.observe({
			command: "nekoc",
			arguments: [root + "/main.neko"],
			expected: "",
			timeoutSeconds: 60
		});
		M14Stage3RuntimeFixture.observe({
			command: "neko",
			arguments: [root + "/main.n"],
			expected: "true\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\n"
		});
		Sys.println("NEKO_ENUM_PAYLOAD_COUNT:PASS");
	}

	static function main():Void
		run();
}
