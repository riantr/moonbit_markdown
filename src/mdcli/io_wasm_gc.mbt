///|
/// The file and process layer for wasm-gc.
///
/// The host that runs a wasm-gc module offers its file system as an
/// unstable module, `__moonbit_fs_unstable`, and strings travel through it
/// in two steps: a string is built on the host side, one character at a
/// time, and read back the same way. There is no process module on this
/// target - the host has none - so the commands that drive a browser cannot
/// work here, and they say so instead of failing quietly.
///
/// The host also aborts the module when a write fails, rather than handing
/// back an error code, so the one failure that can be seen coming - a
/// directory that is not there - is looked for before the write is tried.

///|
/// A string being built on the host side.
#external
priv type XStringCreateHandle

///|
/// A string that lives on the host side.
#external
priv type XExternString

///|
/// A string being read from the host side.
#external
priv type XStringReadHandle

///|
fn begin_create_string() -> XStringCreateHandle = "__moonbit_fs_unstable" "begin_create_string"

///|
fn string_append_char(handle : XStringCreateHandle, ch : Char) = "__moonbit_fs_unstable" "string_append_char"

///|
fn finish_create_string(handle : XStringCreateHandle) -> XExternString = "__moonbit_fs_unstable" "finish_create_string"

///|
fn begin_read_string(s : XExternString) -> XStringReadHandle = "__moonbit_fs_unstable" "begin_read_string"

///|
/// The next character of a string on the host side, or -1 at its end.
fn string_read_char(handle : XStringReadHandle) -> Int32 = "__moonbit_fs_unstable" "string_read_char"

///|
fn finish_read_string(handle : XStringReadHandle) = "__moonbit_fs_unstable" "finish_read_string"

///|
fn path_exists_ffi(path : XExternString) -> Bool = "__moonbit_fs_unstable" "path_exists"

///|
fn read_file_to_string_ffi(path : XExternString) -> XExternString = "__moonbit_fs_unstable" "read_file_to_string"

///|
/// Write a string to a file. 0 means it was written.
fn write_string_to_file_ffi(
  path : XExternString,
  content : XExternString,
) -> Int32 = "__moonbit_fs_unstable" "write_string_to_file"

///|
/// Take a file away. 0 means it is gone.
fn remove_file_ffi(path : XExternString) -> Int32 = "__moonbit_fs_unstable" "remove_file"

///|
/// The string as a string the host understands.
fn to_extern(s : String) -> XExternString {
  let handle = begin_create_string()
  for c in s.iter() {
    string_append_char(handle, c)
  }
  finish_create_string(handle)
}

///|
/// The string the host holds, as a string here.
fn from_extern(s : XExternString) -> String {
  let handle = begin_read_string(s)
  let out = StringBuilder()
  let mut c = string_read_char(handle)
  while c != -1 {
    match c.to_char() {
      Some(ch) => out.write_char(ch)
      None => ()
    }
    c = string_read_char(handle)
  }
  finish_read_string(handle)
  out.to_string()
}

///|
/// The directory a path is in, or an empty string when it has none.
///
/// A drive on its own is not a directory: "C:\out.html" is in the root of
/// the drive, and "C:" names the current directory of the drive, which is
/// not something to look for.
fn parent_dir(path : String) -> String {
  let cs = @text.chars(path)
  let mut cut = -1
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '/' || cs[i] == '\\' {
      cut = i
    }
    i += 1
  }
  if cut <= 0 {
    ""
  } else {
    let dir = @text.text(cs, 0, cut)
    if dir.has_suffix(":") {
      ""
    } else {
      dir
    }
  }
}

///|
/// Whether a path is there.
fn io_exists(path : String) -> Bool {
  path_exists_ffi(to_extern(path))
}

///|
/// The first path of the list that is there, or None when none of them is.
fn io_first_existing(paths : Array[String]) -> String? {
  for p in paths {
    if path_exists_ffi(to_extern(p)) {
      return Some(p)
    }
  }
  None
}

///|
/// The content of a file, or None when it cannot be read.
fn io_read_text(path : String) -> String? {
  if !path_exists_ffi(to_extern(path)) {
    return None
  }
  Some(from_extern(read_file_to_string_ffi(to_extern(path))))
}

///|
/// Write a file, and say whether it was written.
fn io_write_text(path : String, content : String) -> Bool {
  // the host aborts the module when a write fails, so the directory is
  // checked first: a path whose directory is not there is the failure that
  // can be seen coming, and it can be reported instead of crashing
  let dir = parent_dir(path)
  if !dir.is_empty() && !path_exists_ffi(to_extern(dir)) {
    return false
  }
  write_string_to_file_ffi(to_extern(path), to_extern(content)) == 0
}

///|
/// Take a file away, and say whether it is gone afterwards.
fn io_remove(path : String) -> Bool {
  if !path_exists_ffi(to_extern(path)) {
    return true
  }
  remove_file_ffi(to_extern(path)) == 0
}

///|
/// The size of a file in bytes, or -1 when it cannot be told.
///
/// The host has no call for the size of a file, so it is measured from the
/// content. What comes back is the number of characters rather than the
/// number of bytes, which is the same number for the ASCII a path usually
/// holds and close enough for the size the tool reports.
fn io_file_size(path : String) -> Int64 {
  match io_read_text(path) {
    Some(t) => t.length().to_int64()
    None => -1L
  }
}

///|
/// Run a program and wait for it, collecting what it said.
///
/// This target cannot: the host it runs on offers no way to start another
/// program, so the answer says that rather than pretending to have tried.
fn io_run(program : String, _args : Array[String]) -> IoResult {
  {
    code: -1,
    out: "",
    err: "this target cannot start another program, so " +
    program +
    " cannot be run here",
  }
}
