package suite;

/** A non-constant argument for a String parameter; upstream reports `haxe.macro.Expr should be String`. */
function main() {
	final base = "specs";
	for (name in SpecBuilder.names(base))
		Sys.println(name);
}
