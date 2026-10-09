import backend.cpp.CppManagedEnumDescriptors;
import backend.cpp.CppManagedRuntime;
import backend.cpp.CppManagedStaticStorage;
import backend.cpp.CppTypedProgramProjection;

/** Compile descriptors from authored enum syntax and observe native allocation through the real runtime. */
class M14CppManagedEnumDescriptorsTest {
	static function program():{projection:CppTypedProgramProjection, source:HxFunctionDecl} {
		final source = "class Main { static function main():Void {} } enum Choice { Empty; Carry(value:Int); } enum Other { Empty; }";
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return {
			projection: new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false)),
			source: HxClassDecl.getFunctions(HxModuleDecl.getClasses(ResolvedModule.getParsed(module).getDecl())[0])[0]
		};
	}

	static function main():Void {
		final fixture = program();
		final selected = fixture.projection;
		final descriptors = new CppManagedEnumDescriptors(selected);
		if (descriptors.findNullarySymbol(TyType.nominal(new TyNominalTypeId('Main.Other'), [])) == null)
			throw 'parameterless enum lost its descriptor';
		if (descriptors.findNullarySymbol(TyType.nominal(new TyNominalTypeId('Main'), [])) != null)
			throw 'ordinary class borrowed enum key storage';
		var payloadRejected = false;
		try
			descriptors.findNullarySymbol(TyType.nominal(new TyNominalTypeId('Main.Choice'), []))
		catch (error:haxe.Exception) {
			if (error.message.indexOf('structural payload comparison') < 0)
				throw error;
			payloadRejected = true;
		}
		if (!payloadRejected)
			throw 'payload enum borrowed ordinal-only key storage';
		final rendered = descriptors.render();
		if (rendered != descriptors.render())
			throw "enum descriptor emission changed between reads";
		var rejected = false;
		final foreign = program().projection.getModules()[0].projection.getClasses()
		.filter(owner -> owner.requireSemanticFacts().getClassIdentity() == "Main.Choice");
		if (foreign.length != 1)
			throw "foreign enum control lost its declaration";
		try
			descriptors.requireSymbol(foreign[0])
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf("exact program-owned enum") < 0)
				throw failure;
			rejected = true;
		}
		if (!rejected)
			throw "foreign enum projection borrowed a descriptor";
		final statics = new CppManagedStaticStorage(selected, "hxhx_statics_enum_test");
		rejected = false;
		try
			statics.singletonMember(foreign[0], 0)
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf("another program") < 0)
				throw failure;
			rejected = true;
		}
		if (!rejected)
			throw "foreign enum projection borrowed singleton storage";
		final choice = selected.getModules()[0].projection.getClasses().filter(owner -> owner.requireSemanticFacts().getClassIdentity() == "Main.Choice")[0];
		for (index in [1, 2, -1]) {
			rejected = false;
			try
				statics.singletonMember(choice, index)
			catch (failure:haxe.Exception) {
				if (failure.message.indexOf("allocated singleton field") < 0)
					throw failure;
				rejected = true;
			}
			if (!rejected)
				throw "payload constructor or invalid tag borrowed singleton storage";
		}
		final output = ".tmp/managed-enum-descriptors";
		new CppManagedRuntime().publish(output);
		final lines = ["#pragma once", "#include \"ManagedValue.hpp\"", rendered];
		for (owner in selected.getModules()[0].projection.getClasses()) {
			final identity = owner.requireSemanticFacts().getClassIdentity();
			if (identity == "Main.Choice" || identity == "Main.Other")
				lines.push("inline const auto& "
					+ (identity == "Main.Choice" ? "choice" : "other")
					+ " = "
					+ descriptors.requireSymbol(owner)
					+ ";");
		}
		sys.io.File.saveContent(output + "/EnumDescriptors.hpp", lines.join("\n"));
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final binary = output + "/observer" + optimization;
			if (Sys.command(timeout, [
				"60",
				compiler,
				"-std=c++17",
				"-Wall",
				"-Wextra",
				"-Werror",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-I",
				output,
				"test/cpp_managed_heap/EnumDescriptorObserver.cpp",
				"-o",
				binary
			]) != 0)
				throw "enum descriptor observer failed native compilation";
			final process = new sys.io.Process(timeout, ["60", binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stderr.length != 0 || stdout != "CPP_MANAGED_ENUM_DESCRIPTORS:PASS\n")
				throw "enum descriptor observer failed: " + stdout + stderr;
		}
		HxFunctionDecl.getBody(fixture.source).push(SExpr(EInt(99), HxPos.unknown()));
		rejected = false;
		try
			descriptors.render()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf("typed body revision mismatch") < 0)
				throw failure;
			rejected = true;
		}
		if (!rejected)
			throw "descriptor emission accepted mutated parsed source";
		Sys.println("CPP_MANAGED_ENUM_DESCRIPTOR_EMISSION:PASS");
	}
}
