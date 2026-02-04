use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::ptr;

use matrix_sdk::config::SyncSettings;
use matrix_sdk::Client;
use once_cell::sync::OnceCell;
use tokio::runtime::Runtime;
use tokio::time::{timeout, Duration};

static RUNTIME: OnceCell<Runtime> = OnceCell::new();

#[repr(C)]
pub struct mx_string_t
{
    pub data: *const c_char,
    pub len: usize,
}

#[repr(C)]
pub struct mx_error_t
{
    pub code: i32,
    pub message: mx_string_t,
}

#[repr(C)]
pub struct mx_result_t
{
    pub ok: i32,
    pub error: mx_error_t,
}

pub struct mx_client_t
{
    client: Client,
}

pub type mx_client_created_cb = Option<extern "C" fn(*mut mx_client_t, mx_result_t, *mut c_void)>;
pub type mx_login_cb = Option<extern "C" fn(mx_result_t, mx_string_t, *mut c_void)>;
pub type mx_sync_cb = Option<extern "C" fn(mx_result_t, *mut c_void)>;
pub type mx_rooms_cb = Option<extern "C" fn(mx_result_t, mx_room_list_t, *mut c_void)>;

#[repr(C)]
pub struct mx_room_list_t
{
    pub room_ids: *mut mx_string_t,
    pub count: usize,
}

struct BridgeError
{
    code: i32,
    message: String,
}

fn runtime() -> &'static Runtime
{
    RUNTIME.get_or_init(|| Runtime::new().expect("failed to initialize tokio runtime"))
}

fn null_string() -> mx_string_t
{
    mx_string_t {
        data: ptr::null(),
        len: 0,
    }
}

fn make_string(value: String) -> mx_string_t
{
    match CString::new(value)
    {
        Ok(cstr) =>
        {
            let len = cstr.as_bytes().len();
            let data = cstr.into_raw();
            mx_string_t { data, len }
        }
        Err(_) =>
        {
            let cstr = CString::new("ffi string contains interior null").unwrap();
            let len = cstr.as_bytes().len();
            let data = cstr.into_raw();
            mx_string_t { data, len }
        }
    }
}

fn make_ok_result() -> mx_result_t
{
    mx_result_t {
        ok: 1,
        error: mx_error_t {
            code: 0,
            message: null_string(),
        },
    }
}

fn make_error_result(error: BridgeError) -> mx_result_t
{
    mx_result_t {
        ok: 0,
        error: mx_error_t {
            code: error.code,
            message: make_string(error.message),
        },
    }
}

fn make_room_list(room_ids: Vec<mx_string_t>) -> mx_room_list_t
{
    if room_ids.is_empty()
    {
        return mx_room_list_t {
            room_ids: ptr::null_mut(),
            count: 0,
        };
    }

    let mut room_ids = room_ids;
    let list = mx_room_list_t {
        room_ids: room_ids.as_mut_ptr(),
        count: room_ids.len(),
    };
    std::mem::forget(room_ids);
    list
}

fn c_str_to_string(value: *const c_char, label: &str) -> Result<String, BridgeError>
{
    if value.is_null()
    {
        return Err(BridgeError {
            code: 2,
            message: format!("{label} is null"),
        });
    }

    let cstr = unsafe { CStr::from_ptr(value) };
    match cstr.to_str()
    {
        Ok(text) => Ok(text.to_string()),
        Err(err) => Err(BridgeError {
            code: 3,
            message: format!("{label} is not valid utf-8: {err}"),
        }),
    }
}

#[no_mangle]
pub extern "C" fn mx_init()
{
    let _ = runtime();
}

#[no_mangle]
pub extern "C" fn mx_client_create(
    homeserver_url: *const c_char,
    cb: mx_client_created_cb,
    user_data: *mut c_void,
)
{
    let Some(cb) = cb else
    {
        return;
    };

    let homeserver_url = match c_str_to_string(homeserver_url, "homeserver_url")
    {
        Ok(value) => value,
        Err(err) =>
        {
            cb(ptr::null_mut(), make_error_result(err), user_data);
            return;
        }
    };

    let user_data_ptr = user_data as usize;
    runtime().spawn(async move
    {
        let result = timeout(Duration::from_secs(15),
                             Client::builder().homeserver_url(homeserver_url).build()).await;
        match result
        {
            Ok(Ok(client)) =>
            {
                let handle = Box::new(mx_client_t { client });
                cb(Box::into_raw(handle), make_ok_result(), user_data_ptr as *mut c_void);
            }
            Ok(Err(err)) =>
            {
                let error = BridgeError {
                    code: 1,
                    message: format!("client create failed: {err}"),
                };
                cb(ptr::null_mut(), make_error_result(error), user_data_ptr as *mut c_void);
            }
            Err(_) =>
            {
                let error = BridgeError {
                    code: 1,
                    message: "client create timed out".to_string(),
                };
                cb(ptr::null_mut(), make_error_result(error), user_data_ptr as *mut c_void);
            }
        }
    });
}

#[no_mangle]
pub extern "C" fn mx_client_free(client: *mut mx_client_t)
{
    if client.is_null()
    {
        return;
    }

    unsafe {
        drop(Box::from_raw(client));
    }
}

#[no_mangle]
pub extern "C" fn mx_client_login_password(
    client: *mut mx_client_t,
    username: *const c_char,
    password: *const c_char,
    cb: mx_login_cb,
    user_data: *mut c_void,
)
{
    let Some(cb) = cb else
    {
        return;
    };

    let handle = match unsafe { client.as_ref() }
    {
        Some(handle) => handle,
        None =>
        {
            let error = BridgeError {
                code: 2,
                message: "client is null".to_string(),
            };
            cb(make_error_result(error), null_string(), user_data);
            return;
        }
    };

    let username = match c_str_to_string(username, "username")
    {
        Ok(value) => value,
        Err(err) =>
        {
            cb(make_error_result(err), null_string(), user_data);
            return;
        }
    };

    let password = match c_str_to_string(password, "password")
    {
        Ok(value) => value,
        Err(err) =>
        {
            cb(make_error_result(err), null_string(), user_data);
            return;
        }
    };

    let client = handle.client.clone();
    let user_data_ptr = user_data as usize;
    runtime().spawn(async move
    {
        let result = client.matrix_auth().login_username(&username, &password).send().await;
        match result
        {
            Ok(response) =>
            {
                let user_id = make_string(response.user_id.to_string());
                cb(make_ok_result(), user_id, user_data_ptr as *mut c_void);
            }
            Err(err) =>
            {
                let error = BridgeError {
                    code: 1,
                    message: format!("login failed: {err}"),
                };
                cb(make_error_result(error), null_string(), user_data_ptr as *mut c_void);
            }
        }
    });
}

#[no_mangle]
pub extern "C" fn mx_client_sync_once(client: *mut mx_client_t, cb: mx_sync_cb, user_data: *mut c_void)
{
    let Some(cb) = cb else
    {
        return;
    };

    let handle = match unsafe { client.as_ref() }
    {
        Some(handle) => handle,
        None =>
        {
            let error = BridgeError {
                code: 2,
                message: "client is null".to_string(),
            };
            cb(make_error_result(error), user_data);
            return;
        }
    };

    let client = handle.client.clone();
    let user_data_ptr = user_data as usize;
    runtime().spawn(async move
    {
        let result = client.sync_once(SyncSettings::default()).await;
        match result
        {
            Ok(_) => cb(make_ok_result(), user_data_ptr as *mut c_void),
            Err(err) =>
            {
                let error = BridgeError {
                    code: 1,
                    message: format!("sync failed: {err}"),
                };
                cb(make_error_result(error), user_data_ptr as *mut c_void);
            }
        }
    });
}

#[no_mangle]
pub extern "C" fn mx_client_rooms(client: *mut mx_client_t, cb: mx_rooms_cb, user_data: *mut c_void)
{
    let Some(cb) = cb else
    {
        return;
    };

    let handle = match unsafe { client.as_ref() }
    {
        Some(handle) => handle,
        None =>
        {
            let error = BridgeError {
                code: 2,
                message: "client is null".to_string(),
            };
            cb(make_error_result(error), mx_room_list_t { room_ids: ptr::null_mut(), count: 0 }, user_data);
            return;
        }
    };

    let client = handle.client.clone();
    let user_data_ptr = user_data as usize;
    runtime().spawn(async move
    {
        let rooms = client.rooms();
        let room_ids = rooms
            .into_iter()
            .map(|room| make_string(room.room_id().to_string()))
            .collect::<Vec<_>>();
        let list = make_room_list(room_ids);
        cb(make_ok_result(), list, user_data_ptr as *mut c_void);
    });
}

#[no_mangle]
pub extern "C" fn mx_string_free(value: mx_string_t)
{
    if value.data.is_null()
    {
        return;
    }

    unsafe {
        drop(CString::from_raw(value.data as *mut c_char));
    }
}

#[no_mangle]
pub extern "C" fn mx_result_free(result: mx_result_t)
{
    mx_string_free(result.error.message);
}

#[no_mangle]
pub extern "C" fn mx_room_list_free(rooms: mx_room_list_t)
{
    if rooms.room_ids.is_null()
    {
        return;
    }

    unsafe {
        let room_ids = Vec::from_raw_parts(rooms.room_ids, rooms.count, rooms.count);
        for room_id in room_ids
        {
            mx_string_free(room_id);
        }
    }
}
