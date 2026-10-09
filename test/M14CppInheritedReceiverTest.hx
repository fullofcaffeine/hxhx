/** Run implicit inherited access through the same native and sanitizer observers as explicit upcasts. */
class M14CppInheritedReceiverTest {
	static function project():backend.cpp.CppTypedProgramProjection {
		final path = "test/oracle/cpp_inherited_storage_seed/BareReceiver.hx";
		final module = new ResolvedModule("BareReceiver", path, ParserStage.parse(sys.io.File.getContent(path), path));
		return new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false));
	}

	/** Equal source and declaration names must not transfer field authority across functions or programs. */
	static function ownership():Void {
		final program = project();
		final storage = new backend.cpp.CppManagedClassStorage(program);
		final foreign = new backend.cpp.CppManagedClassStorage(project());
		final child = program.requireClass(program.requireClassIdentity("BareReceiver.BareChild")).getFunctions()[0];
		final base = program.requireClass(program.requireClassIdentity("BareReceiver.BareBase")).getFunctions()[0];
		var checked = 0;
		for (statement in child.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				final field = child.findField(expression);
				if (field == null)
					return;
				storage.assertImplicitFieldReceiver(child, field);
				for (check in [
					() -> foreign.assertImplicitFieldReceiver(child, field),
					() -> storage.assertImplicitFieldReceiver(base, field)
				]) {
					var rejected = false;
					try
						check()
					catch (_:haxe.Exception)
						rejected = true;
					if (!rejected)
						throw "foreign inherited field occurrence was accepted";
				}
				checked++;
			}, _ -> {});
		if (checked != 2)
			throw "inherited read/write ownership controls did not run";
		Sys.println("CPP_INHERITED_RECEIVER_OWNERSHIP:PASS");
	}

	static function main():Void {
		ownership();
		M14CppInheritedStorageTest.exercise("BareReceiver", ".tmp/cpp-inherited-receiver");
		M14CppInheritedStorageTest.exercise("CapturedReceiver", ".tmp/cpp-inherited-receiver-captured");
		Sys.println("CPP_INHERITED_RECEIVER:PASS");
	}
}
