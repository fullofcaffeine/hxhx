package consumer;

import sample.Provider.*;

/** Exercise a wildcard import while skipping optional String arguments before a Bool. **/
class Main {
	static function main():Void {
		install("account", "repository", true);
	}
}
