import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a `.length` program with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- Stage3 lowers `x.length` to `HxString.length` or `HxBootArray.length`
	  only when it can tell from typed facts that `x` is a `String` or an
	  `Array`. A receiver that it could not classify fell back to a dynamic
	  record-field lookup. A string or array has no such record field, so the
	  native program printed `null` where upstream prints a number.
	- Instance and static field reads (`box.text`), index expressions
	  (`parts[1]`), and `Null<String>` call results (`maybe(true)`) all took
	  that fallback.

	What
	- `stage3_member_length` reads `.length` from each of those receiver shapes
	  and from a `String` returned by an instance call (`s.substr(1)`). It also
	  reads `.length` from a null `String`, a null `Array`, and a null `String`
	  field inside `try`/`catch`: upstream throws a catchable error there, so the
	  native program must throw one too instead of crashing.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- A member read on a `String` or `Array` receiver that the emitter cannot
	  lower must stop emission with a named error instead of returning `null`.
**/
class M14Stage3MemberLengthTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function compareWithUpstream(label:String, source:String, expectedPath:String):Void {
		final path = source + "/Main.hx";
		final expected = File.getContent(expectedPath);
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_member_length_" + label;
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_MEMBER_LENGTH_" + label.toUpperCase() + ":PASS");
	}

	/**
		A member read that still reaches the dynamic record lookup on a typed
		String or Array receiver must stop emission with a named error.

		Every member that typed String and Array receivers expose today has a
		native lowering or an earlier named rejection, so no source program
		reaches this lookup. The check exercises the guard directly with the
		same typed facts the emitter passes it, so a future receiver shape that
		loses its lowering fails loudly instead of printing `null`.
	**/
	static function rejectDynamicLookup():Void {
		final string = TyType.fromHintText("String");
		final array = TyType.nominal(new TyNominalTypeId("Array"), [TyType.fromHintText("Int")]);
		for (entry in [
			{type: string, receiver: "String"},
			{type: TyType.nullable(string), receiver: "String"},
			{type: array, receiver: "Array"},
			{type: TyType.nullable(array), receiver: "Array"}
		]) {
			var message:Null<String> = null;
			try {
				backend.ocaml.Stage3OcamlMemberLength.rejectDynamicLookup(entry.type, "size");
			} catch (error:String) {
				message = error;
			}
			final expected = "stage3 emitter: member `size` on a " + entry.receiver + " receiver has no native lowering";
			if (message == null || message.indexOf(expected) < 0)
				throw "expected <" + expected + "> for " + entry.type.getSemanticKey() + ", got <" + message + ">";
		}
		// Dynamic, unknown, and other receivers keep their dynamic lookup.
		backend.ocaml.Stage3OcamlMemberLength.rejectDynamicLookup(TyType.fromHintText("Dynamic"), "size");
		backend.ocaml.Stage3OcamlMemberLength.rejectDynamicLookup(null, "size");
		backend.ocaml.Stage3OcamlMemberLength.rejectDynamicLookup(TyType.fromHintText("Int"), "size");
		Sys.println("M14_STAGE3_MEMBER_LENGTH_REJECT_DYNAMIC_LOOKUP:PASS");
	}

	static function main():Void {
		compareWithUpstream("whole_file", "test/fixtures/stage3_member_length", "test/fixtures/stage3_member_length/expected.stdout");
		rejectDynamicLookup();
	}
}
