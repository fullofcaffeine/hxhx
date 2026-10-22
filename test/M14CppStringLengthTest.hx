/** Compile real String fields, then execute independently observed lengths under native sanitizers. */
class M14CppStringLengthTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_string_length_seed",
			mainModule: "StringLength",
			requiredModules: ["String"]
		});
		final program = new backend.cpp.CppTypedProgramProjection(CppResolvedFixture.prepare(fixture));
		final owner = program.requireClass(program.requireClassIdentity("StringLength"));
		final classes = new backend.cpp.CppManagedClassStorage(program);
		ownership(owner, classes);
		final functions = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) != "shadow");
		final header = new backend.cpp.CppManagedProgramEmitter({
			functions: [
				for (fn in functions)
					{
						projection: fn,
						rootSymbol: "generated_" + HxFunctionDecl.getName(fn.getDeclaration()),
						symbolPrefix: "hxhx_function_" + HxFunctionDecl.getName(fn.getDeclaration())
					}
			],
			output: [],
			classes: classes
		}).render();
		program.assertCurrent();
		final output = ".tmp/cpp-string-length";
		sys.FileSystem.createDirectory(output);
		new backend.cpp.CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + "/Generated.hpp", '#include "ManagedString.hpp"\n' + classes.render() + "\n" + header);
		CppManagedAssertionFixture.sanitizers(output, "CPP_STRING_LENGTH", "test/cpp_managed_heap/StringLengthObserver.cpp", "Generated.hpp");
		Sys.println("CPP_STRING_LENGTH:PASS");
	}

	/** Same-named fields, copied syntax and a changed owning body cannot borrow standard-field permission. */
	static function ownership(owner:TypedBackendClassProjection, classes:backend.cpp.CppManagedClassStorage):Void {
		for (name in ["read", "shadow"]) {
			final fn = owner.getFunctions().filter(candidate -> HxFunctionDecl.getName(candidate.getDeclaration()) == name)[0];
			final expression = switch fn.getBody()[0] {
				case SReturn(value, _): value;
				case _: throw "String.length fixture lost its field return";
			};
			final field = fn.findField(expression);
			if (field == null || backend.cpp.CppManagedStringLength.selects(field) != (name == "read"))
				throw "String.length confused standard and authored fields";
			if (name == "shadow") {
				reject(() -> backend.cpp.CppManagedStringLength.require(field), "exact standard field");
				continue;
			}
			backend.cpp.CppManagedStringLength.require(field);
			final access = new backend.cpp.CppManagedLocalAccess({
				projection: fn,
				plan: new backend.cpp.CppManagedStoragePlan(fn),
				owner: Root(fn),
				parameters: ["value"],
				temporaryPrefix: "hxhx_parameters_length_"
			});
			final reader = new backend.cpp.CppManagedRootedExpression({
				owner: CallableBody(access),
				classes: classes,
				heap: "heap",
				temporaryPrefix: "hxhx_value_length_",
				resolve: _ -> throw "String.length fixture has no nested closure"
			});
			if (reader.valueType(expression).getSemanticKey() != "primitive:Int")
				throw "String.length lost its Int result";
			reader.render(expression, "result", "");
			final copied = switch expression {
				case EField(receiver, name): HxExpr.EField(receiver, name);
				case _: throw "String.length fixture lost its field";
			};
			reject(() -> reader.valueType(copied), "not an exact expression");
			reject(() -> reader.render(copied, "result", ""), "not an exact expression");
			final body = fn.getBody();
			body.push(SExpr(EInt(99), HxPos.unknown()));
			reject(() -> reader.render(expression, "result", ""), "projection was mutated");
			body.pop();
			reader.render(expression, "result", "");
		}
		Sys.println("CPP_STRING_LENGTH_OWNERSHIP:PASS");
	}

	/** Require the intended ownership error rather than accepting an unrelated compilation failure. */
	static function reject(action:Void->Void, message:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(message) < 0)
				throw error;
			return;
		}
		throw "String.length accepted invalid ownership";
	}
}
