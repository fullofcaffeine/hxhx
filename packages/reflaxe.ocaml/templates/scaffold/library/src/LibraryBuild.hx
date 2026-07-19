/** Keeps the starter library entry points reachable during target generation. **/
class LibraryBuild {
	static function main():Void {
		final message = sample.Greeting.message("library user");
		if (message.length == 0) {
			throw "The starter greeting must not be empty.";
		}
	}
}
