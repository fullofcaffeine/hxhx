package sample;

/** Produce observable output only when the imported function actually executes. **/
class Provider {
	public static function install(account:String, repository:String, ?branch:String, ?sourcePath:String, retry:Bool = false, ?alternateName:String):Void {
		Sys.println("imported-call:executed");
	}
}
