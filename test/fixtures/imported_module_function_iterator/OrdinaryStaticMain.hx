import Functions;

/** Upstream must reject an ordinary class method used as a bare module function. */
class OrdinaryStaticMain {
	static function main():Void
		classValue();
}
