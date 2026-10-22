package backend.cpp;

/** Bind shared startup ordering to this exact C++ program and its resolved module imports. */
class CppManagedStartupOrder {
	final order:TypedStaticStartupOrder;

	public function new(program:CppTypedProgramProjection) {
		order = new TypedStaticStartupOrder({
			modules: [
				for (module in program.getModules())
					{
						moduleIdentity: module.moduleIdentity,
						projection: module.projection,
						importedClasses: program.getImportedClasses(module.projection)
					}
			],
			assertCurrent: program.assertCurrent
		});
	}

	/** Target defaults and execution remain C++ policy; this only returns the complete class order. */
	public function getClasses():Array<TypedBackendClassProjection>
		return order.getClasses();
}
