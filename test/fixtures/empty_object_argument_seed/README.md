Run `npm run test:m14:empty-object-argument` to compare upstream Haxe with emitted JavaScript.
The program passes empty objects through a Dynamic argument, writes different fields, and checks that the objects stay distinct.
The test also preserves empty-brace macro syntax and verifies that empty function bodies still require an explicit return when their declared result is Dynamic.
