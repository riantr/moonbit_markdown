///|
/// The file and process layer for native and wasm.
///
/// Both targets have the toolchain's async runtime, and both have it behind
/// an asynchronous interface: there is no synchronous `read_text` to call,
/// and an asynchronous function cannot be called from a synchronous one.
/// The runtime does have a driver that runs an asynchronous body to
/// completion and then returns - the same one the toolchain itself calls
/// for `async fn main` - and that is what this file uses.
///
/// So the tool is synchronous on every target, and the asynchronous runtime
/// stays a detail of these two rather than a shape the whole tool has to be
/// built in. The price is one runtime start per operation, which is a price
/// a command line tool can pay: it does a handful of file operations and
/// then exits.

///|
/// Run an asynchronous body to completion, and return when it is done.
///
/// The body is handed to the runtime's own driver. The runtime reports a
/// failure by exiting the process, so every operation below catches its own
/// errors: a failure has to be a value the caller can look at, not a way
/// for the program to stop in the middle.
fn sync_run(body : async () -> Unit) -> Unit {
  @async.run_async_main(body)
}

///|
/// Whether a path is there.
fn io_exists(path : String) -> Bool {
  let r : Ref[Bool] = Ref(false)
  sync_run(() => r.val = @fs.exists(path))
  r.val
}

///|
/// The first path of the list that is there, or None when none of them is.
///
/// The whole list is looked at inside one run of the runtime, because the
/// lookup is a loop over the places the mermaid runtime may be, and a
/// runtime start per path would cost more than the lookup.
fn io_first_existing(paths : Array[String]) -> String? {
  let r : Ref[String?] = Ref(None)
  sync_run(() => {
    for p in paths {
      if @fs.exists(p) {
        r.val = Some(p)
        break
      }
    }
  })
  r.val
}

///|
/// The content of a file, or None when it cannot be read.
///
/// A file that is there but empty reads as an empty string, and a file that
/// is not there reads as None: the two are different answers and the caller
/// needs to tell them apart.
fn io_read_text(path : String) -> String? {
  let failed : Ref[Bool] = Ref(false)
  let text : Ref[String] = Ref("")
  sync_run(() => {
    let t = @fs.read_text(path) catch {
      _ => {
        failed.val = true
        ""
      }
    }
    if !failed.val {
      text.val = t
    }
  })
  if failed.val {
    None
  } else {
    Some(text.val)
  }
}

///|
/// Write a file, and say whether it was written.
///
/// The write is checked rather than trusted: a path that cannot be written
/// to is a failure, and a page that was never written must not be reported
/// as one that was.
fn io_write_text(path : String, content : String) -> Bool {
  let failed : Ref[Bool] = Ref(false)
  let r : Ref[Bool] = Ref(false)
  sync_run(() => {
    @fs.write_text(path, content) catch {
      _ => failed.val = true
    }
    if !failed.val {
      r.val = @fs.exists(path)
    }
  })
  r.val
}

///|
/// Take a file away, and say whether it is gone afterwards.
fn io_remove(path : String) -> Bool {
  let failed : Ref[Bool] = Ref(false)
  let r : Ref[Bool] = Ref(false)
  sync_run(() => {
    @fs.remove(path) catch {
      _ => failed.val = true
    }
    if !failed.val {
      r.val = !@fs.exists(path)
    }
  })
  r.val
}

///|
/// The size of a file in bytes, or -1 when it cannot be told.
fn io_file_size(path : String) -> Int64 {
  let r : Ref[Int64] = Ref(-1L)
  sync_run(() => r.val = @fs.file_size(path) catch { _ => -1L })
  r.val
}

///|
/// Run a program and wait for it, collecting what it said.
///
/// The output is collected rather than inherited: the browser's DOM comes
/// back on the output stream, and it is the answer the measurement needs.
fn io_run(program : String, args : Array[String]) -> IoResult {
  let r : Ref[IoResult] = Ref({ code: -1, out: "", err: "", })
  sync_run(() => {
    let p = @process.run(program, args, stdout=Collect, stderr=Collect)
    let out = p.stdout_text() catch { _ => "" }
    let err = p.stderr_text() catch { _ => "" }
    r.val = { code: p.exit_code, out, err, }
  })
  r.val
}
