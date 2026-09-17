This fixture checks that `catch (value:Any)` receives the original Neko throw
carrier. Strings, integers, existing exceptions, and wrapped exceptions retain
their values or identities. A user class named `custom.Any` remains a typed
catch and does not intercept an unrelated string.

Run this command from the repository root:

```sh
haxe -cp test -cp packages/hxhx-core/src -cp packages/hxhx/src --run M14NekoTypedCatchIntegrationTest test/neko_any_catch
```

The observer compares upstream Haxe 4.3.7 with both native Neko output layouts.
This fixture also runs in the typed-catch integration group. It does not
establish complete exception compatibility.
