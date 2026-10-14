#+build windows
package main

import win32 "core:sys/windows"

// Makes a file read-only, or writable again, for the tests of a save that cannot
// write: the read-only attribute, set without opening the file, which core:os's
// change_mode does and cannot once the file is read-only. True when done.
set_read_only :: proc(path: string, read_only: bool) -> bool {
	name := win32.utf8_to_wstring(path, context.temp_allocator)
	attributes := win32.GetFileAttributesW(name)
	if attributes == win32.INVALID_FILE_ATTRIBUTES do return false
	if read_only {
		attributes |= win32.FILE_ATTRIBUTE_READONLY
	} else {
		attributes &~= win32.FILE_ATTRIBUTE_READONLY
	}
	return bool(win32.SetFileAttributesW(name, attributes))
}
