package backend.vm;

import backend.vm.NekoTypedProgramProjection.NekoProjectedFunction;

/**
	The single executable projection whose expressions a Neko scope can consume.

	Nested blocks and lambdas retain this owner. Entering a declared function or
	field initializer replaces it, so two catalogs cannot compete for a marker.
**/
enum NekoExecutableProjection {
	FunctionBody(functionProjection:NekoProjectedFunction);
	FieldInitializer(initializer:TypedBackendFieldInitializerProjection);
}
