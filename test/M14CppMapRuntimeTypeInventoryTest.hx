/**
	Checks the declaration inventory needed by the C++ map runtime contract.

	Typing must retain all four exact Map targets and their executable revisions.
	M14CppRuntimeTypeMapTest separately proves native behavior and protects existing
	artifacts when an erased value has no supported runtime representation.
**/
class M14CppMapRuntimeTypeInventoryTest {
	static function main():Void {
		final program = CppMapFixture.load();
		final expected = [
			"haxe.ds.IntMap",
			"haxe.ds.StringMap",
			"haxe.ds.ObjectMap",
			"haxe.ds.EnumValueMap"
		];
		final found = new haxe.ds.StringMap<Bool>();
		// This inventory belongs to the four authored tests in Main. The complete
		// dependency closure also contains its own runtime operations; the native
		// integration test must admit or reject those through normal publication.
		for (module in program.getTypedModules()) {
			if (module.getSourceOrigin().sourceModulePath != "Main")
				continue;
			for (cls in module.getBackendProjection().getClasses())
				for (fn in cls.getFunctions())
					for (entry in fn.getRuntimeTypeCatalog().getEntries()) {
						final selected = fn.requireRuntimeType(entry.getExpression());
						selected.assertOwner(fn.getStableIdentity(), fn.getBodyRevision());
						final identity = selected.getTarget().requireDeclarationIdentity().getCanonicalName();
						if (selected != entry || selected.getValue() == null || expected.indexOf(identity) < 0 || found.exists(identity))
							throw "map type test lost its exact occurrence: " + identity;
						found.set(identity, true);
						var rejected = false;
						try {
							fn.getRuntimeTypeCatalog().require(entry.getExpression(), fn.getStableIdentity(), "stale");
						} catch (_:haxe.Exception) {
							rejected = true;
						}
						if (!rejected)
							throw "map occurrence accepted a stale body revision";
					}
		}
		for (identity in expected)
			if (!found.exists(identity))
				throw "map provider did not resolve: " + identity;
		assertRuntimePlan(program);
		assertInitializerPlan();

		Sys.println("CPP_MAP_RUNTIME_TYPE_INVENTORY:PASS");
	}

	/** Real provider bodies need descriptors too, even before their execution is admitted. */
	static function assertRuntimePlan(program:MacroExpandedProgram):Void {
		final projection = new backend.cpp.CppTypedProgramProjection(program);
		final plan = new backend.cpp.CppRuntimeTypePlan(projection);
		final descriptors = plan.getDescriptors();
		final expected = [
			"runtime-core:Array",
			"runtime-nominal:Math",
			"runtime-nominal:haxe.Int64.___Int64",
			"runtime-nominal:haxe.ds.EnumValueMap",
			"runtime-nominal:haxe.ds.IntMap",
			"runtime-nominal:haxe.ds.ObjectMap",
			"runtime-nominal:haxe.ds.StringMap"
		];
		// The real closure includes Math.__init__. Int64's __Int64 typedef must
		// resolve to its concrete ___Int64 class rather than become a descriptor.
		final actual = [for (descriptor in descriptors) descriptor.getTarget().getSemanticKey()];
		if (actual.join("\n") != expected.join("\n"))
			throw "runtime descriptor plan omitted or duplicated a real provider: " + actual.join(", ");
		for (descriptor in descriptors) {
			final declaration = descriptor.getTarget().requireDeclarationIdentity().getCanonicalName();
			final owner = projection.requireClass(projection.requireClassIdentity(declaration)).requireSemanticFacts();
			if (descriptor.getDeclaration() != owner)
				throw "runtime descriptor lost exact declaration owner: " + declaration;
		}
		var tests = 0;
		var values = 0;
		var arrays = 0;
		final operations = plan.getOperations();
		for (operation in operations) {
			switch operation.kind {
				case InstanceTest:
					tests++;
				case ClassValue:
					values++;
			}
			if (operation.occurrence.getTarget().getSemanticKey() == "runtime-core:Array") {
				arrays++;
				if (operation.descriptor != descriptors[0])
					throw "repeated Array operands must share one descriptor";
			}
		}
		if (tests != 4 || values != 4 || arrays != 2)
			throw "runtime plan confused Map instance tests with provider class values";
		descriptors.pop();
		operations.pop();
		if (plan.getDescriptors().length != 7 || plan.getOperations().length != 8)
			throw "runtime plan exposed its mutable inventory";
		final marker = plan.getOperations()[0].occurrence.getExpression();
		switch marker {
			case ECall(_, arguments):
				arguments.push(EInt(0));
				var rejected = false;
				try {
					plan.getOperations();
				} catch (error:haxe.Exception) {
					rejected = error.message == "runtime type occurrence marker was mutated";
				}
				arguments.pop();
				if (!rejected)
					throw "runtime plan accepted a mutated occurrence";
			case _:
				throw "runtime fixture did not produce an owned marker";
		}
		plan.assertCurrent();
		for (kind in [
			TypedRuntimeTypeKind.IntCore,
			TypedRuntimeTypeKind.FloatCore,
			TypedRuntimeTypeKind.BoolCore
		]) {
			final descriptor = new backend.cpp.CppRuntimeTypePlan.CppRuntimeTypeDescriptor(new TypedRuntimeTypeTarget(kind), projection);
			if (descriptor.getDeclaration() != null)
				throw "primitive type object acquired a synthetic declaration";
		}
	}

	/** Static class-valued fields must use their own initializer occurrence catalog. */
	static function assertInitializerPlan():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/runtime_class_value_seed/array",
			mainModule: "Main",
			requiredModules: ["Array", "Std"]
		});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final projection = new backend.cpp.CppTypedProgramProjection(program);
		final plan = new backend.cpp.CppRuntimeTypePlan(projection);
		final main = projection.requireClass(projection.requireClassIdentity("Main"));
		var found = false;
		for (initializer in main.getFieldInitializers()) {
			if (HxFieldDecl.getName(initializer.getDeclaration()) != "selected")
				continue;
			for (entry in initializer.getRuntimeTypeCatalog().getEntries()) {
				final occurrence = initializer.requireRuntimeType(entry.getExpression());
				for (operation in plan.getOperations())
					if (operation.occurrence == occurrence) {
						if (operation.kind != ClassValue || operation.descriptor.getTarget().getSemanticKey() != "runtime-core:Array")
							throw "initializer class value lost its exact kind or target";
						found = true;
					}
			}
		}
		if (!found)
			throw "runtime plan omitted the static class-valued initializer";
	}
}
