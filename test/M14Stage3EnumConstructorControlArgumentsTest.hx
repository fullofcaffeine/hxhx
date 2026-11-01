import sys.io.File;

/**
	Build enum values whose constructor arguments need statements first.

	A comprehension, block, `if`, `switch`, `try` or closure call used as a
	constructor argument makes control lowering run that argument's statements
	before the call. The constructor must stay an exact enum construction rather
	than a captured first-class value, and a lambda that returns an enum value
	must keep the enum's `Obj.t` box as its native result. The fixture also builds
	`haxe.macro.Expr` values the way macro reification does. Upstream
	`haxe --interp` output, including argument evaluation order, is the oracle.
 */
class M14Stage3EnumConstructorControlArgumentsTest {
	static function main():Void {
		final root = "test/fixtures/stage3_enum_constructor_control_arguments";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: root});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), ".tmp/stage3-enum-constructor-control-arguments", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_ENUM_CONSTRUCTOR_CONTROL_ARGUMENTS:PASS");
	}
}
