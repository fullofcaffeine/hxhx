package suite;

/** An Int constant for a String parameter; upstream reports `Int should be String`. */
function main() {
	for (name in SpecBuilder.names(1))
		Sys.println(name);
}
