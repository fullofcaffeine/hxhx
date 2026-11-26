class Main {
	static final name = "Ada";
	static final a = 2;
	static final b = 3;

	static function main():Void {
		Sys.println(Fmt.format("plain text"));
		Sys.println(Fmt.format("Hello $name!"));
		Sys.println(Fmt.format("$name first"));
		Sys.println(Fmt.format("${a + b} items"));
		Sys.println(Fmt.format("${a}${b}"));
		Sys.println(Fmt.format("nested ${{x: a}.x}"));
		Sys.println(Fmt.format("cost $$5, 5$, $1 and $"));
		Sys.println(Fmt.format("it's $name, ${a}'s"));
		Sys.println(Fmt.format("say \"hi\" to $name"));
		Sys.println("[" + Fmt.format("") + "]");
		Sys.println(Fmt.shape("plain text"));
		Sys.println(Fmt.shape("Hello $name!"));
		Sys.println(Fmt.shape("$name first"));
		Sys.println(Fmt.shape("${a + b} items"));
		Sys.println(Fmt.shape("${a}${b}"));
		Sys.println(Fmt.shape("nested ${{x: a}.x}"));
		Sys.println(Fmt.shape("cost $$5, 5$, $1 and $"));
		Sys.println(Fmt.shape("it's $name, ${a}'s"));
		Sys.println(Fmt.shape("say \"hi\" to $name"));
		Sys.println(Fmt.shape(""));
	}
}
