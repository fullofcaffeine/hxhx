package backend.cpp;

/** Exact native source bytes and their path-independent identity at compiler build time. */
typedef CppManagedRuntimeFile = {
	final name:String;
	final content:String;
	final sha256:String;
}

/**
	Publish the compiler's embedded managed runtime beside generated C++ sources.
	Runtime execution never searches the checkout or installed Haxe library paths.
	The build macro reads the authored headers and registers their dependencies;
	this object retains that immutable snapshot for one output publication.
	Publication provides native memory primitives, not source-semantic admission.
 */
class CppManagedRuntime {
	final files:Array<CppManagedRuntimeFile>;

	public function new() {
		files = CppManagedRuntimeMacro.files();
	}

	public function getFiles():Array<CppManagedRuntimeFile>
		return files.copy();

	/** Write only this bundle's named headers and return their normal backend artifact records. */
	public function publish(directory:String):Array<backend.EmitArtifact> {
		if (directory == null || directory.length == 0)
			throw "managed runtime publication requires an output directory";
		sys.FileSystem.createDirectory(directory);
		final artifacts = new Array<backend.EmitArtifact>();
		for (file in files) {
			final path = haxe.io.Path.join([directory, file.name]);
			sys.io.File.saveContent(path, file.content);
			artifacts.push(new backend.EmitArtifact("cpp_managed_runtime_header", path));
		}
		return artifacts;
	}
}
