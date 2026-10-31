package hxhxmacrohost;

#if ocaml
@:native("HxHxMacroModuleDynlink")
private extern class NativeMacroModuleHostIdentityRuntime {
	@:native("host_ocaml_version")
	public static function ocamlVersion():String;

	@:native("host_executable_digest")
	public static function executableDigest():String;

	@:native("host_pid")
	public static function processId():Int;
}
#end

/**
	Identity of the running hxhx binary, as a project-macro plugin must match it.

	Why
	- A project-macro plugin is OCaml code that Dynlink loads into the compiler process. It links
	  against the compiler's own runtime units, so it is only safe to load into the exact binary
	  whose runtime it was built against, and only when it was compiled by the same OCaml version.
	  A plain `hxhx` binary does not know which commit it was built from, but it can digest its own
	  executable file; that digest changes whenever the binary is rebuilt.
	- Reading the OCaml version and hashing a file are runtime primitives. The handwritten
	  `HxHxMacroModuleDynlink` adapter returns the two values; Haxe (`ProjectMacroPluginCache`)
	  decides what they mean for cache keys, receipts, and diagnostics.

	What
	- `ocamlVersion()`: the OCaml version that compiled the running binary (`Sys.ocaml_version`).
	- `executableDigest()`: an MD5 digest, in hexadecimal, of the running executable file. It is a
	  cache identity, not a security check; artifacts are checked with SHA-256 separately.
	- `processId()`: the compiler's process id, recorded as the owner of a plugin build lock.
	- The first two throw outside an OCaml-native hxhx (for example under `haxe --interp`), where no
	  plugin can be loaded anyway; tests pass their own identity to the cache instead. Under the
	  interpreter `processId()` asks a shell for its parent's id, so lock tests can run there.
**/
class NativeMacroModuleHostIdentity {
	public static function ocamlVersion():String {
		#if ocaml
		return NativeMacroModuleHostIdentityRuntime.ocamlVersion();
		#else
		throw "project macro plugins require an OCaml-native hxhx binary";
		#end
	}

	public static function executableDigest():String {
		#if ocaml
		return NativeMacroModuleHostIdentityRuntime.executableDigest();
		#else
		throw "project macro plugins require an OCaml-native hxhx binary";
		#end
	}

	public static function processId():Int {
		#if ocaml
		return NativeMacroModuleHostIdentityRuntime.processId();
		#else
		final process = new sys.io.Process("/bin/sh", ["-c", "echo $PPID"]);
		final pid = Std.parseInt(StringTools.trim(process.stdout.readAll().toString()));
		process.close();
		if (pid == null)
			throw "could not read the compiler process id";
		return pid;
		#end
	}
}
