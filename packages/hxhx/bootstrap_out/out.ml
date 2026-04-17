# 1 "out.ml"
let () =
  HxType.set_registry_init_hook HxTypeRegistry.init;
  ignore (Hxhx_Main.main ())
