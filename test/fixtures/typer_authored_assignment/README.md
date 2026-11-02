# Typer: values entering written types

`cases.txt` lists small programs, one per line. Each one assigns a value to a
local with a written type, or returns a value from a function with a declared
return type:

- `NEG|<message>|<class Main body>|<other declarations>`: upstream Haxe 4.3.7
  rejects the program with `<message>` (for example `Float should be Int` for
  `var g:Float->Int = f` with `f:(Int)->Int`);
- `POS||...`: upstream accepts it.

`npm run test:m14:typer-authored-assignment` checks every line against upstream
Haxe first, then requires the hxhx typer to accept or reject it the same way.
The POS lines cover function variance, Int widening to Float, Void results,
Dynamic, optional arguments, generic methods, abstracts, enum abstracts,
subclasses, interfaces, structures, and nullable values.
