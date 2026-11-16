//! Thin FFI glue over the rxminer library. Mining, Stratum, configuration and
//! the HTTP API all come from upstream; this file only owns one session thread.
use clap::Parser;
use rxminer::config::{Cli, Options};
use serde_json::{json, Value};
use std::{
    ffi::{CStr, CString},
    os::raw::c_char,
    panic::{catch_unwind, AssertUnwindSafe},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread::{self, JoinHandle},
};

struct Session {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
    error: Arc<Mutex<Option<String>>>,
}

static SESSION: Mutex<Option<Session>> = Mutex::new(None);

fn output(value: Value) -> *mut c_char {
    CString::new(value.to_string())
        .unwrap_or_default()
        .into_raw()
}

fn guarded(action: impl FnOnce() -> Result<Value, String>) -> *mut c_char {
    output(
        match catch_unwind(AssertUnwindSafe(action)).unwrap_or_else(|_| Err("native panic".into())) {
            Ok(value) => value,
            Err(error) => json!({ "error": error }),
        },
    )
}

/// Arguments are a JSON array of command-line flags, without the program name.
unsafe fn cli(args: *const c_char) -> Result<Cli, String> {
    if args.is_null() {
        return Err("missing arguments".into());
    }
    // SAFETY: the caller passes a live NUL-terminated string.
    let text = unsafe { CStr::from_ptr(args) }
        .to_str()
        .map_err(|_| "arguments are not UTF-8".to_string())?;
    let args: Vec<String> =
        serde_json::from_str(text).map_err(|error| format!("invalid arguments: {error}"))?;
    Cli::try_parse_from(std::iter::once("rxminer".to_string()).chain(args))
        .map_err(|error| error.to_string().trim().to_string())
}

fn options(cli: Cli) -> Result<Options, String> {
    Options::from_cli(cli).map_err(|error| format!("{error:#}"))
}

/// Physical CPU selection and memory as seen by the miner.
#[no_mangle]
pub extern "C" fn rxminer_device() -> *mut c_char {
    guarded(|| {
        let cores = rxminer::topology::discover().map_err(|error| format!("{error:#}"))?;
        let quota = rxminer::topology::cpu_quota();
        let selected = rxminer::topology::select(&cores, quota.unwrap_or(0), false);
        Ok(json!({
            "logical": cores.len(),
            "selected": selected.len(),
            "nodes": cores.iter().map(|c| c.node).collect::<std::collections::BTreeSet<_>>().len(),
            "summary": rxminer::topology::summary(&selected),
            "memory": rxminer::topology::available_memory(),
            "jit": rxminer::randomx::JIT_SUPPORTED,
            "arch": std::env::consts::ARCH,
            "os": std::env::consts::OS,
        }))
    })
}

/// Validates arguments and configuration like `--dry-run`. Reports the
/// worker count and whether the arguments describe an offline benchmark.
///
/// # Safety
/// `args` must be a NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn rxminer_check(args: *const c_char) -> *mut c_char {
    guarded(|| {
        // SAFETY: forwarded caller contract.
        let options = options(unsafe { cli(args) }?)?;
        let all = rxminer::topology::discover().map_err(|error| format!("{error:#}"))?;
        let cores = options
            .select_cores(&all, rxminer::topology::cpu_quota())
            .map_err(|error| format!("{error:#}"))?;
        Ok(json!({ "threads": cores.len(), "benchmark": options.benchmark.is_some() }))
    })
}

/// Starts one in-process session. Fails if a session is still running.
///
/// # Safety
/// `args` must be a NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn rxminer_start(args: *const c_char) -> *mut c_char {
    guarded(|| {
        // SAFETY: forwarded caller contract.
        let cli = unsafe { cli(args) }?;
        let options = options(cli.clone())?;
        let mut slot = SESSION.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(session) = slot.as_mut() {
            if session.thread.as_ref().is_some_and(|t| !t.is_finished()) {
                return Err("the miner is already running".into());
            }
            if let Some(thread) = session.thread.take() {
                let _ = thread.join();
            }
        }
        if let Err(error) = rxminer::logging::configure(&options) {
            return Err(format!("{error:#}"));
        }
        let stop = Arc::new(AtomicBool::new(false));
        let error = Arc::new(Mutex::new(None));
        let thread = {
            let stop = stop.clone();
            let error = error.clone();
            thread::Builder::new()
                .name("rxminer".into())
                .spawn(move || {
                    let result = catch_unwind(AssertUnwindSafe(|| {
                        rxminer::runtime::run(options, cli, stop)
                    }));
                    let message = match result {
                        Ok(Ok(())) => None,
                        Ok(Err(e)) => Some(format!("{e:#}")),
                        Err(_) => Some("the miner panicked".into()),
                    };
                    if let Some(message) = &message {
                        rxminer::status!("rxminer: {message}");
                    }
                    *error.lock().unwrap_or_else(|p| p.into_inner()) = message;
                })
                .map_err(|e| format!("start miner thread: {e}"))?
        };
        *slot = Some(Session {
            stop,
            thread: Some(thread),
            error,
        });
        Ok(json!({}))
    })
}

/// Requests a stop. Returns at once; poll `rxminer_state` until it ends.
#[no_mangle]
pub extern "C" fn rxminer_stop() -> *mut c_char {
    guarded(|| {
        if let Some(session) = SESSION.lock().unwrap_or_else(|p| p.into_inner()).as_ref() {
            session.stop.store(true, Ordering::Release);
        }
        Ok(json!({}))
    })
}

#[no_mangle]
pub extern "C" fn rxminer_state() -> *mut c_char {
    guarded(|| {
        let slot = SESSION.lock().unwrap_or_else(|p| p.into_inner());
        let Some(session) = slot.as_ref() else {
            return Ok(json!({ "running": false, "stopping": false, "error": null }));
        };
        let running = session.thread.as_ref().is_some_and(|t| !t.is_finished());
        Ok(json!({
            "running": running,
            "stopping": running && session.stop.load(Ordering::Acquire),
            "error": *session.error.lock().unwrap_or_else(|p| p.into_inner()),
        }))
    })
}

/// # Safety
/// `value` must come from this library and be freed once.
#[no_mangle]
pub unsafe extern "C" fn rxminer_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: allocated by CString::into_raw above.
        drop(unsafe { CString::from_raw(value) });
    }
}
