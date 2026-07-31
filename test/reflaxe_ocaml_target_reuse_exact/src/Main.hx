/**
 * Small executable used to prove that exact target replay preserves behavior.
 *
 * The XML access also loads Haxe's private dot-resolution abstracts. Haxe 4.3.7
 * exposes their resolve hooks as placeholder fields, so cold and warm requests
 * must fingerprint that host shape without dropping it or crashing. This base
 * fixture remains eligible for an exact cache hit; the separate RTTI stage
 * proves that unstable compiler-generated input instead fails closed.
 */
class Main {
	/**
	 * Keeps the Access type in the final program without exercising unrelated
	 * XML runtime lowering. The cache test cares about its compiler fingerprint.
	 */
	@:keep
	static var xmlAccessType:haxe.xml.Access;

	static function main():Void {
		Sys.println("exact target replay");
	}
}
