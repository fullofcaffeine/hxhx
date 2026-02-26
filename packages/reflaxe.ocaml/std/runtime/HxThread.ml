(* Runtime thread primitives for reflaxe.ocaml.

   Scope
   - Provides the minimal backend-native substrate needed by std overrides under
     `std/_std/sys/thread/*`.
   - Keeps payloads as `Obj.t` at API boundaries because Haxe thread/message/TLS
     surfaces are dynamically typed.

   Design notes
   - Each primitive family uses integer handles backed by internal tables.
   - Blocking operations use OCaml threads primitives (`Thread`, `Mutex`, `Condition`).
   - Timeout support for lock/semaphore uses cooperative polling where no direct
     timed wait primitive exists in OCaml's condition API.
*)

let null_value : Obj.t = HxRuntime.hx_null
let poll_interval_seconds = 0.001

let with_mutex (mutex : Mutex.t) (f : unit -> 'a) : 'a =
  Mutex.lock mutex;
  try
    let result = f () in
    Mutex.unlock mutex;
    result
  with exn ->
    Mutex.unlock mutex;
    raise exn

let now_seconds () : float =
  Unix.gettimeofday ()

let sleep_small (seconds : float) : unit =
  if seconds <= 0.0 then ()
  else Thread.delay (if seconds < poll_interval_seconds then seconds else poll_interval_seconds)

(* -------------------------------------------------------------------------- *)
(* Lock *)
(* -------------------------------------------------------------------------- *)

type lock_state = {
  mutex : Mutex.t;
  condition : Condition.t;
  mutable permits : int;
}

let next_lock_id = ref 1
let lock_table : (int, lock_state) Hashtbl.t = Hashtbl.create 16
let lock_table_mutex = Mutex.create ()

let get_lock_exn (id : int) : lock_state =
  with_mutex lock_table_mutex (fun () ->
      match Hashtbl.find_opt lock_table id with
      | Some state -> state
      | None -> failwith ("HxThread.lock: invalid handle " ^ string_of_int id))

let lock_create () : int =
  let id =
    with_mutex lock_table_mutex (fun () ->
        let id = !next_lock_id in
        incr next_lock_id;
        let state = { mutex = Mutex.create (); condition = Condition.create (); permits = 0 } in
        Hashtbl.add lock_table id state;
        id)
  in
  id

let lock_release (id : int) : unit =
  let state = get_lock_exn id in
  with_mutex state.mutex (fun () ->
      state.permits <- state.permits + 1;
      Condition.signal state.condition)

let lock_wait_internal (state : lock_state) (deadline : float option) : bool =
  with_mutex state.mutex (fun () ->
      let rec loop () =
        if state.permits > 0 then (
          state.permits <- state.permits - 1;
          true)
        else
          match deadline with
          | None ->
              Condition.wait state.condition state.mutex;
              loop ()
          | Some stop_at ->
              let remaining = stop_at -. now_seconds () in
              if remaining <= 0.0 then
                false
              else (
                Mutex.unlock state.mutex;
                sleep_small remaining;
                Mutex.lock state.mutex;
                loop ())
      in
      loop ())

let lock_wait (id : int) : bool =
  let state = get_lock_exn id in
  lock_wait_internal state None

let lock_wait_timeout (id : int) (timeout : float) : bool =
  let state = get_lock_exn id in
  if timeout <= 0.0 then
    lock_wait_internal state (Some (now_seconds ()))
  else
    lock_wait_internal state (Some (now_seconds () +. timeout))

(* -------------------------------------------------------------------------- *)
(* Mutex *)
(* -------------------------------------------------------------------------- *)

type mutex_state = Mutex.t

let next_mutex_id = ref 1
let mutex_table : (int, mutex_state) Hashtbl.t = Hashtbl.create 16
let mutex_table_mutex = Mutex.create ()

let get_mutex_exn (id : int) : mutex_state =
  with_mutex mutex_table_mutex (fun () ->
      match Hashtbl.find_opt mutex_table id with
      | Some state -> state
      | None -> failwith ("HxThread.mutex: invalid handle " ^ string_of_int id))

let mutex_create () : int =
  with_mutex mutex_table_mutex (fun () ->
      let id = !next_mutex_id in
      incr next_mutex_id;
      Hashtbl.add mutex_table id (Mutex.create ());
      id)

let mutex_acquire (id : int) : unit =
  Mutex.lock (get_mutex_exn id)

let mutex_try_acquire (id : int) : bool =
  Mutex.try_lock (get_mutex_exn id)

let mutex_release (id : int) : unit =
  Mutex.unlock (get_mutex_exn id)

(* -------------------------------------------------------------------------- *)
(* Condition *)
(* -------------------------------------------------------------------------- *)

type condition_state = {
  mutex : Mutex.t;
  condition : Condition.t;
}

let next_condition_id = ref 1
let condition_table : (int, condition_state) Hashtbl.t = Hashtbl.create 16
let condition_table_mutex = Mutex.create ()

let get_condition_exn (id : int) : condition_state =
  with_mutex condition_table_mutex (fun () ->
      match Hashtbl.find_opt condition_table id with
      | Some state -> state
      | None -> failwith ("HxThread.condition: invalid handle " ^ string_of_int id))

let condition_create () : int =
  with_mutex condition_table_mutex (fun () ->
      let id = !next_condition_id in
      incr next_condition_id;
      Hashtbl.add condition_table id { mutex = Mutex.create (); condition = Condition.create () };
      id)

let condition_acquire (id : int) : unit =
  let state = get_condition_exn id in
  Mutex.lock state.mutex

let condition_try_acquire (id : int) : bool =
  let state = get_condition_exn id in
  Mutex.try_lock state.mutex

let condition_release (id : int) : unit =
  let state = get_condition_exn id in
  Mutex.unlock state.mutex

let condition_wait (id : int) : unit =
  let state = get_condition_exn id in
  Condition.wait state.condition state.mutex

let condition_signal (id : int) : unit =
  let state = get_condition_exn id in
  Condition.signal state.condition

let condition_broadcast (id : int) : unit =
  let state = get_condition_exn id in
  Condition.broadcast state.condition

(* -------------------------------------------------------------------------- *)
(* Semaphore *)
(* -------------------------------------------------------------------------- *)

type semaphore_state = {
  mutex : Mutex.t;
  condition : Condition.t;
  mutable value : int;
}

let next_semaphore_id = ref 1
let semaphore_table : (int, semaphore_state) Hashtbl.t = Hashtbl.create 16
let semaphore_table_mutex = Mutex.create ()

let get_semaphore_exn (id : int) : semaphore_state =
  with_mutex semaphore_table_mutex (fun () ->
      match Hashtbl.find_opt semaphore_table id with
      | Some state -> state
      | None -> failwith ("HxThread.semaphore: invalid handle " ^ string_of_int id))

let semaphore_create (value : int) : int =
  with_mutex semaphore_table_mutex (fun () ->
      let id = !next_semaphore_id in
      incr next_semaphore_id;
      Hashtbl.add semaphore_table id
        { mutex = Mutex.create (); condition = Condition.create (); value = max 0 value };
      id)

let semaphore_acquire (id : int) : unit =
  let state = get_semaphore_exn id in
  with_mutex state.mutex (fun () ->
      let rec loop () =
        if state.value > 0 then
          state.value <- state.value - 1
        else (
          Condition.wait state.condition state.mutex;
          loop ())
      in
      loop ())

let semaphore_try_acquire (id : int) : bool =
  let state = get_semaphore_exn id in
  with_mutex state.mutex (fun () ->
      if state.value > 0 then (
        state.value <- state.value - 1;
        true)
      else
        false)

let semaphore_try_acquire_timeout (id : int) (timeout : float) : bool =
  let state = get_semaphore_exn id in
  let deadline = now_seconds () +. timeout in
  with_mutex state.mutex (fun () ->
      let rec loop () =
        if state.value > 0 then (
          state.value <- state.value - 1;
          true)
        else
          let remaining = deadline -. now_seconds () in
          if remaining <= 0.0 then
            false
          else (
            Mutex.unlock state.mutex;
            sleep_small remaining;
            Mutex.lock state.mutex;
            loop ())
      in
      loop ())

let semaphore_release (id : int) : unit =
  let state = get_semaphore_exn id in
  with_mutex state.mutex (fun () ->
      state.value <- state.value + 1;
      Condition.signal state.condition)

(* -------------------------------------------------------------------------- *)
(* Deque *)
(* -------------------------------------------------------------------------- *)

type deque_state = {
  mutex : Mutex.t;
  condition : Condition.t;
  mutable values : Obj.t list;
}

let next_deque_id = ref 1
let deque_table : (int, deque_state) Hashtbl.t = Hashtbl.create 16
let deque_table_mutex = Mutex.create ()

let get_deque_exn (id : int) : deque_state =
  with_mutex deque_table_mutex (fun () ->
      match Hashtbl.find_opt deque_table id with
      | Some state -> state
      | None -> failwith ("HxThread.deque: invalid handle " ^ string_of_int id))

let deque_create () : int =
  with_mutex deque_table_mutex (fun () ->
      let id = !next_deque_id in
      incr next_deque_id;
      Hashtbl.add deque_table id { mutex = Mutex.create (); condition = Condition.create (); values = [] };
      id)

let deque_add (id : int) (value : Obj.t) : unit =
  let state = get_deque_exn id in
  with_mutex state.mutex (fun () ->
      state.values <- state.values @ [ value ];
      Condition.signal state.condition)

let deque_push (id : int) (value : Obj.t) : unit =
  let state = get_deque_exn id in
  with_mutex state.mutex (fun () ->
      state.values <- value :: state.values;
      Condition.signal state.condition)

let deque_pop (id : int) (block : bool) : Obj.t =
  let state = get_deque_exn id in
  with_mutex state.mutex (fun () ->
      let rec loop () =
        match state.values with
        | head :: tail ->
            state.values <- tail;
            head
        | [] ->
            if not block then
              null_value
            else (
              Condition.wait state.condition state.mutex;
              loop ())
      in
      loop ())

(* -------------------------------------------------------------------------- *)
(* Thread-local storage *)
(* -------------------------------------------------------------------------- *)

type tls_state = (int, Obj.t) Hashtbl.t

let next_tls_id = ref 1
let tls_table : (int, tls_state) Hashtbl.t = Hashtbl.create 16
let tls_table_mutex = Mutex.create ()

let current_thread_id () : int =
  Thread.id (Thread.self ())

let get_tls_exn (id : int) : tls_state =
  with_mutex tls_table_mutex (fun () ->
      match Hashtbl.find_opt tls_table id with
      | Some state -> state
      | None -> failwith ("HxThread.tls: invalid handle " ^ string_of_int id))

let tls_create () : int =
  with_mutex tls_table_mutex (fun () ->
      let id = !next_tls_id in
      incr next_tls_id;
      Hashtbl.add tls_table id (Hashtbl.create 8);
      id)

let tls_get (id : int) : Obj.t =
  let state = get_tls_exn id in
  let thread_id = current_thread_id () in
  with_mutex tls_table_mutex (fun () ->
      match Hashtbl.find_opt state thread_id with
      | Some value -> value
      | None -> null_value)

let tls_set (id : int) (value : Obj.t) : unit =
  let state = get_tls_exn id in
  let thread_id = current_thread_id () in
  with_mutex tls_table_mutex (fun () ->
      if value == null_value then
        Hashtbl.remove state thread_id
      else
        Hashtbl.replace state thread_id value)

(* -------------------------------------------------------------------------- *)
(* Thread message queues + event-loop attachment *)
(* -------------------------------------------------------------------------- *)

type mailbox_state = {
  mutex : Mutex.t;
  condition : Condition.t;
  mutable values : Obj.t list;
}

let mailbox_table : (int, mailbox_state) Hashtbl.t = Hashtbl.create 16
let mailbox_table_mutex = Mutex.create ()

let create_mailbox () : mailbox_state =
  { mutex = Mutex.create (); condition = Condition.create (); values = [] }

let ensure_mailbox (thread_id : int) : mailbox_state =
  with_mutex mailbox_table_mutex (fun () ->
      match Hashtbl.find_opt mailbox_table thread_id with
      | Some mailbox -> mailbox
      | None ->
          let mailbox = create_mailbox () in
          Hashtbl.add mailbox_table thread_id mailbox;
          mailbox)

let () =
  ignore (ensure_mailbox (current_thread_id ()))

let mailbox_push (mailbox : mailbox_state) (value : Obj.t) : unit =
  with_mutex mailbox.mutex (fun () ->
      mailbox.values <- mailbox.values @ [ value ];
      Condition.signal mailbox.condition)

let mailbox_pop (mailbox : mailbox_state) (block : bool) : Obj.t =
  with_mutex mailbox.mutex (fun () ->
      let rec loop () =
        match mailbox.values with
        | head :: tail ->
            mailbox.values <- tail;
            head
        | [] ->
            if not block then
              null_value
            else (
              Condition.wait mailbox.condition mailbox.mutex;
              loop ())
      in
      loop ())

let thread_current () : int =
  current_thread_id ()

let thread_create (job : unit -> unit) : int =
  let mailbox = create_mailbox () in
  let wrapped () =
    let id = current_thread_id () in
    with_mutex mailbox_table_mutex (fun () -> Hashtbl.replace mailbox_table id mailbox);
    job ()
  in
  let thread_handle = Thread.create wrapped () in
  let thread_id = Thread.id thread_handle in
  with_mutex mailbox_table_mutex (fun () -> Hashtbl.replace mailbox_table thread_id mailbox);
  thread_id

let thread_send_message (target_handle : int) (message : Obj.t) : unit =
  mailbox_push (ensure_mailbox target_handle) message

let thread_read_message (block : bool) : Obj.t =
  mailbox_pop (ensure_mailbox (current_thread_id ())) block

let events_table : (int, Obj.t) Hashtbl.t = Hashtbl.create 16
let events_table_mutex = Mutex.create ()

let thread_get_events (handle : int) : Obj.t =
  with_mutex events_table_mutex (fun () ->
      match Hashtbl.find_opt events_table handle with
      | Some value -> value
      | None -> null_value)

let thread_set_events (handle : int) (event_loop : Obj.t) : unit =
  with_mutex events_table_mutex (fun () ->
      if event_loop == null_value then
        Hashtbl.remove events_table handle
      else
        Hashtbl.replace events_table handle event_loop)
