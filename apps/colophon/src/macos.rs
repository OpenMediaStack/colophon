//! Cmd+Q and Quit in the app menu end a macOS app through `terminate:`, which never asks its
//! window to close. Winit's application delegate leaves `applicationShouldTerminate:` out, so
//! Colophon adds it: the window is asked instead, and may first ask what to do with unsaved
//! changes.

#![allow(unsafe_code)]

use std::cell::RefCell;

use colophon_ui::{AppWindow, ComponentHandle};
use objc2::runtime::{AnyClass, AnyObject, Imp, Sel};
use objc2::{ffi, sel};

/// `NSApplicationTerminateReply`.
const TERMINATE_CANCEL: usize = 0;
const TERMINATE_NOW: usize = 1;

type ShouldTerminate = extern "C-unwind" fn(&AnyObject, Sel, *mut AnyObject) -> usize;

thread_local! {
    static CLOSE_WINDOW: RefCell<Option<Box<dyn Fn() -> bool>>> = RefCell::default();
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
