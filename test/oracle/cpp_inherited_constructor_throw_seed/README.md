The inherited-constructor test runs this fixture with upstream Haxe and the native failure observer.

The child has no constructor. Its second declared field allocates an object before its first declared field throws. The ancestor body must remain unexecuted. The native observer checks the exact failure and checks that collection releases construction roots and the allocated objects.
