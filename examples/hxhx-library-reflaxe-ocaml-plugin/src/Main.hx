import AddedFromPlugin;

class Main {
  static function main() {
    #if HXHX_PLUGIN_FIXTURE
    trace("plugin_define=ok");
    #else
    trace("plugin_define=missing");
    #end

    AddedFromPlugin.ping();
    trace("main=ok");
  }
}
