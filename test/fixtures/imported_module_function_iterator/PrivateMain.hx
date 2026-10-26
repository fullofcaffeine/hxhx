import Functions;

/** Upstream must reject a private module function through a plain import. */
class PrivateMain {
	static function main():Void
		hidden();
}
