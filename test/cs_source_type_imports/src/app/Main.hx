package app;

import left.Provider as LeftProvider;
import right.Provider as RightProvider;
import model.Bundle.Secondary as SecondaryProvider;
import RootProvider;

/** Observe calls through distinct imported owners without relying on reflection. */
class Main {
	static function main():Void {
		LeftProvider.visitLeft();
		RightProvider.visitRight();
		SecondaryProvider.visitSecondary();
		RootProvider.visitRoot();
		Local.visitLocal();
		Sys.println(new LeftProvider() != null ? "left" : "missing");
		Sys.println(new RightProvider() != null ? "right" : "missing");
		Sys.println("secondary");
		Sys.println(new RootProvider() != null ? "root" : "missing");
		Sys.println(new Local() != null ? "local" : "missing");
	}
}
