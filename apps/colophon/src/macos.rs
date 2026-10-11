//! What macOS needs beyond Slint and winit.
//!
//! Cmd+Q and Quit in the app menu end a macOS app through `terminate:`, which never asks its
//! window to close. Winit's application delegate leaves `applicationShouldTerminate:` out, so
//! Colophon adds it: the window is asked instead, and may first ask what to do with unsaved
//! changes.
//!
//! Outside an app bundle, as under `cargo run`, the Dock shows no icon for the app: Colophon
//! shows its own.
//!
//! The About item of the app menu, which Slint makes, opens AppKit's standard panel: Colophon
//! opens its own dialog instead, with the licenses of what it ships.

#![allow(unsafe_code)]

use std::cell::RefCell;
use std::ffi::c_void;

use colophon_ui::{AppWindow, ComponentHandle};
use objc2::runtime::{AnyClass, AnyObject, Imp, Sel};
use objc2::{ffi, msg_send, sel};

/// `NSApplicationTerminateReply`.
const TERMINATE_CANCEL: usize = 0;
const TERMINATE_NOW: usize = 1;

type ShouldTerminate = extern "C-unwind" fn(&AnyObject, Sel, *mut AnyObject) -> usize;
/// `orderFrontStandardAboutPanel:`.
type AboutPanel = extern "C-unwind" fn(&AnyObject, Sel, *mut AnyObject);

thread_local! {
    static CLOSE_WINDOW: RefCell<Option<Box<dyn Fn() -> bool>>> = RefCell::default();
    static SHOW_ABOUT: RefCell<Option<Box<dyn Fn()>>> = RefCell::default();
}

/// The icon of the Dock and the app switcher, large enough for the largest Retina Dock.
const ICON: &[u8] = include_bytes!("../../../assets/icon/png/colophon-1024.png");

/// Shows Colophon's icon in the Dock and the app switcher. Must run once the event loop runs:
/// launching gives the Dock the icon of the app bundle, or the generic one without a bundle,
/// whatever was set before.
pub fn show_icon() {
    let (Some(data), Some(image), Some(application)) = (
        AnyClass::get(c"NSData"),
        AnyClass::get(c"NSImage"),
        AnyClass::get(c"NSApplication"),
    ) else {
        return;
    };
    // SAFETY: each message is one these Foundation and AppKit classes answer, with arguments of
    // the types they take, on the main thread where winit runs: `dataWithBytes:length:` gives
    // autoreleased data, which `initWithData:` reads, and `setApplicationIconImage:` takes the
    // image or nil. The image made with `alloc` is never released: it lasts as long as the app.
    unsafe {
        let bytes: *mut AnyObject =
            msg_send![data, dataWithBytes: ICON.as_ptr().cast::<c_void>(), length: ICON.len()];
        let allocated: *mut AnyObject = msg_send![image, alloc];
        let icon: *mut AnyObject = msg_send![allocated, initWithData: bytes];
        let app: *mut AnyObject = msg_send![application, sharedApplication];
        let _: () = msg_send![app, setApplicationIconImage: icon];
    }
}

/// Must run once the event loop exists, which creating the window ensures.
pub fn ask_window_before_terminating(window: &AppWindow) {
    let Some(delegate) = AnyClass::get(c"WinitApplicationDelegate") else {
        return;
    };
    let window = window.as_weak();
    CLOSE_WINDOW.set(Some(Box::new(move || {
        window
            .upgrade()
            .is_none_or(|window| colophon_ui::request_close(&window))
    })));
    let should_terminate: ShouldTerminate = should_terminate;
    // SAFETY: the method's type encoding matches `ShouldTerminate`: an `NSUInteger` returned, then
    // the receiver, the selector and the sender. Adding a method the class lacks changes nothing
    // else, and winit only runs it on the main thread, where `CLOSE_WINDOW` lives.
    unsafe {
        let imp = std::mem::transmute::<ShouldTerminate, Imp>(should_terminate);
        ffi::class_addMethod(
            std::ptr::from_ref(delegate).cast_mut(),
            sel!(applicationShouldTerminate:),
            imp,
            c"Q@:@".as_ptr(),
        );
    }
}

extern "C-unwind" fn should_terminate(_: &AnyObject, _: Sel, _: *mut AnyObject) -> usize {
    let closed = CLOSE_WINDOW.with_borrow(|close| close.as_ref().is_none_or(|close| close()));
    if closed {
        TERMINATE_NOW
    } else {
        TERMINATE_CANCEL
    }
}

/// Must run once the event loop exists, which creating the window ensures.
pub fn show_about_from_app_menu(window: &AppWindow) {
    let Some(method) = AnyClass::get(c"NSApplication")
        .and_then(|application| application.instance_method(sel!(orderFrontStandardAboutPanel:)))
    else {
        return;
    };
    let window = window.as_weak();
    SHOW_ABOUT.set(Some(Box::new(move || {
        if let Some(window) = window.upgrade() {
            window.invoke_show_about();
        }
    })));
    let show_about: AboutPanel = show_about;
    // SAFETY: `show_about` has the type of `orderFrontStandardAboutPanel:`: nothing returned,
    // then the receiver, the selector and the sender. AppKit only sends it on the main thread,
    // where `SHOW_ABOUT` lives.
    unsafe {
        method.set_implementation(std::mem::transmute::<AboutPanel, Imp>(show_about));
    }
}

extern "C-unwind" fn show_about(_: &AnyObject, _: Sel, _: *mut AnyObject) {
    SHOW_ABOUT.with_borrow(|show| {
        if let Some(show) = show {
            show();
        }
    });
}
