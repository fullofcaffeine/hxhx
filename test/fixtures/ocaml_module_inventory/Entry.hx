import Mixed.Helper;

/** A module-level entrypoint still selects its real callable projection. */
function main():Void {
	Sys.println("entry");
	Sys.println(Helper.value());
}
