package pk;

/** Declared in another module, so `Main` sees its values only through an expected type. **/
enum abstract Mode(Int) to Int {
	var Fast = 1;
	var Slow = 2;
}
