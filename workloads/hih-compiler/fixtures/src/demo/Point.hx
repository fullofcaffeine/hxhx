package demo;

/**
	Stage 3.3 typing fixture: instance fields + this + constructor.

	Why
	- Gate 1 needs the typer to understand basic class shapes:
	  - instance fields (`var x:Int`)
	  - constructors (`function new(...)`)
	  - `this` field access (`this.x`)

	What
	- A minimal `Point` class with a single `Int` field and a constructor that
	  initializes it.

	How
	- The constructor uses `this.x = x`, which exercises:
	  - parsing `this` + field access
	  - typing `this.x` via the program index
**/
class Point {
	public var x:Int;

	public function new(x:Int) {
		this.x = x;
	}

	public function getX():Int return this.x;
}

