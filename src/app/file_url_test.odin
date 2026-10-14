package main

import "core:testing"

@(test)
file_urls_encode_what_a_url_cannot_hold :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, file_url("/Users/me/Music"), "file:///Users/me/Music")
	testing.expect_value(t, file_url("/Users/me/My Music"), "file:///Users/me/My%20Music")
	testing.expect_value(t, file_url("/Users/me/Été"), "file:///Users/me/%C3%89t%C3%A9")
	testing.expect_value(t, file_url("/a#b%c"), "file:///a%23b%25c")
	testing.expect_value(t, file_url("C:\\Users\\me"), "file:///C:/Users/me")
}
