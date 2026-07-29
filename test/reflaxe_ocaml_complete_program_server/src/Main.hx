/**
	Small whole-program fixture for clean-versus-server output comparison.

	The request matrix edits dependencies, class-path winners, configuration, and
	build-macro output around this root. Each successful state prints its selected
	values so generated-source equality is backed by native runtime behavior.
**/
class Main {
	static function main():Void {
		Sys.println("message=" + Message.text());
		Sys.println("api=" + Api.value());
		Sys.println("shadow=" + Shadowed.value());
		Sys.println("macro=" + MacroBuilt.generated());
		#if feature_enabled
		Sys.println("feature=" + Feature.value());
		#end
	}
}
