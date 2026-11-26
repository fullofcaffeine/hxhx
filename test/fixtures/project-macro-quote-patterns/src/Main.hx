class Main {
	static function main():Void {
		final count = 33;
		Sys.println(Markup.unprocessed("<xml a=\"1\"></xml>"));
		Sys.println(Markup.unprocessed("<$xml></$xml>"));
		Sys.println(Markup.pipe("<xml>$count + ${count * 2}</xml>"));
		Sys.println(Markup.pipe("{ <a></a><b /> }"));
	}
}
