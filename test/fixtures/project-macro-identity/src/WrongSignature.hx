/**
	Negative caller for the identity macro smoke.

	The macro receives a function whose parameter is not `label`, so its signature check throws.
	Compilation must fail at this call with the macro's own message; it must not fall back to
	compiling the call as an ordinary function call.
**/
class WrongSignature {
	static function main():Void {
		final check = Identity.preserve(function(other:String):String {
			return other;
		});
		Sys.println(check("ok"));
	}
}
