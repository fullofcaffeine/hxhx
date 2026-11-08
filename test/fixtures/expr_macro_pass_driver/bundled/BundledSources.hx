/** Calls hxhx's own bundled-source macro from `packages/hxhx-core/src` (the compile adds that classpath). */
class BundledSources {
	static function main():Void {
		final files = CompilerBundledSourcesMacro.files();
	}
}
