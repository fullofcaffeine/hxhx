package backend.cpp;

/**
	Register the exact source method in its program-owned stack context.
	Method identity comes from checked declarations. Source-line tracking and
	closure identities require their own exact plans; no native symbol parsing
	or fabricated file position fills those gaps.
 */
function entry(projection:TypedBackendFunctionProjection, owner:CppManagedFunctionOwner, storage:CppManagedStaticStorage):Array<String> {
	storage.assertFunction(projection);
	switch owner {
		case Root(selected):
			if (selected != projection)
				throw "managed stack frame belongs to another function";
		case Closure(_):
			throw "managed debug stack requires exact closure frame metadata";
	}
	final declaration = projection.requireSemanticDeclaration();
	return ["  static const hxhx::managed::StackFrameInfo hxhx_frame_info{"
		+ haxe.Json.stringify(declaration.getOwner().getCanonicalName())
		+ ", "
		+ haxe.Json.stringify(declaration.getSignature().getName())
		+ ', "", 0};',
		"  hxhx::managed::StackFrame hxhx_frame(" + storage.stackAccess("hxhx_heap") + ", hxhx_frame_info);"
	];
}
