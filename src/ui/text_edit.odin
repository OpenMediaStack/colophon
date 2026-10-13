package ui

import "base:runtime"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

// The systems whose text editing conventions differ: word moves and their keys.
Platform :: enum u8 {
	Mac,
	Windows,
	Linux,
}

PLATFORM ::
	Platform.Mac when ODIN_OS ==
	.Darwin else (Platform.Windows when ODIN_OS == .Windows else Platform.Linux)

// The text of the field being edited, with its caret, its selection and its own undo
// history. Offsets are in bytes, always on a character boundary. Make it with
// text_edit_init, free it with text_edit_destroy.
Text_Edit :: struct {
	buffer: [dynamic]u8,
	caret:  int,
	// The other end of the selection; equal to caret when nothing is selected.
	anchor: int,
	undo:   [dynamic]Edit_Step,
	redo:   [dynamic]Edit_Step,
	// What the last change did, so that typing a word is one step to undo.
	last:   Edit_Kind,
}

// What a field's text was before a change, and where its caret and selection were.
@(private)
Edit_Step :: struct {
	text:          string,
	caret, anchor: int,
}

@(private)
Edit_Kind :: enum u8 {
	None,
	Typing,
	Deleting,
}

text_edit_init :: proc(e: ^Text_Edit, allocator := context.allocator) {
	e.buffer = make([dynamic]u8, allocator)
	e.undo = make([dynamic]Edit_Step, allocator)
	e.redo = make([dynamic]Edit_Step, allocator)
}

text_edit_destroy :: proc(e: ^Text_Edit) {
	clear_history(e)
	delete(e.buffer)
	delete(e.undo)
	delete(e.redo)
	e^ = {}
}

// The text being edited. It changes with the next edit.
edit_text :: proc(e: ^Text_Edit) -> string {
	return string(e.buffer[:])
}

// The selected text, empty when nothing is selected.
selected_text :: proc(e: ^Text_Edit) -> string {
	return string(e.buffer[min(e.caret, e.anchor):max(e.caret, e.anchor)])
}

has_selection :: proc(e: ^Text_Edit) -> bool {
	return e.caret != e.anchor
}

// Starts editing text, everything selected or the caret at its end, with an empty
// history.
edit_reset :: proc(e: ^Text_Edit, text: string, select_all: bool) {
	clear(&e.buffer)
	append(&e.buffer, text)
	e.caret = len(e.buffer)
	e.anchor = select_all ? 0 : e.caret
	clear_history(e)
	e.last = .None
}

// Puts the caret at offset, extending the selection when extend.
edit_move :: proc(e: ^Text_Edit, offset: int, extend := false) {
	e.caret = clamp(offset, 0, len(e.buffer))
	if !extend do e.anchor = e.caret
	e.last = .None
}

edit_select_all :: proc(e: ^Text_Edit) {
	e.anchor = 0
	e.caret = len(e.buffer)
	e.last = .None
}

// Selects the word around offset, or the run of spaces or the punctuation there: a
// double click.
edit_select_word :: proc(e: ^Text_Edit, offset: int) {
	s := edit_text(e)
	at := clamp(offset, 0, len(s))
	if at == len(s) && at > 0 do at = previous_char(s, at)
	if len(s) == 0 do return
	r, _ := utf8.decode_rune_in_string(s[at:])
	class := char_class(r)
	start, end := at, at
	for start > 0 {
		before := previous_char(s, start)
		c, _ := utf8.decode_rune_in_string(s[before:])
		if char_class(c) != class do break
		start = before
	}
	for end < len(s) {
		c, n := utf8.decode_rune_in_string(s[end:])
		if char_class(c) != class do break
		end += n
	}
	e.anchor, e.caret = start, end
	e.last = .None
}

// Replaces the selection with text, which loses its line breaks: a field holds one
// line.
edit_insert :: proc(e: ^Text_Edit, text: string) {
	if len(text) == 0 do return
	remember(e, .Typing)
	delete_selection(e)
	for r in text {
		if r == '\n' || r == '\r' do continue
		bytes, n := utf8.encode_rune(r)
		inject_at(&e.buffer, e.caret, ..bytes[:n])
		e.caret += n
	}
	e.anchor = e.caret
}

// Deletes the selection, or from the caret to offset.
edit_delete_to :: proc(e: ^Text_Edit, offset: int) {
	if !has_selection(e) && offset == e.caret do return
	remember(e, .Deleting)
	if !has_selection(e) do e.anchor = clamp(offset, 0, len(e.buffer))
	delete_selection(e)
}

// Goes back to the text before the last step; false when there is none.
edit_undo :: proc(e: ^Text_Edit) -> bool {
	step, ok := pop_safe(&e.undo)
	if !ok do return false
	append(&e.redo, swap(e, step))
	return true
}

// Goes forward again to the text of the last step undone; false when there is none.
edit_redo :: proc(e: ^Text_Edit) -> bool {
	step, ok := pop_safe(&e.redo)
	if !ok do return false
	append(&e.undo, swap(e, step))
	return true
}

// The offset of the character before offset.
previous_char :: proc(s: string, offset: int) -> int {
	at := min(offset, len(s)) - 1
	for at > 0 && !utf8.rune_start(s[at]) do at -= 1
	return max(at, 0)
}

// The offset of the character after offset.
next_char :: proc(s: string, offset: int) -> int {
	if offset >= len(s) do return len(s)
	_, n := utf8.decode_rune_in_string(s[offset:])
	return offset + n
}

// Where the caret goes to move a word left: the start of the word before it, on every
// system.
word_left :: proc(s: string, offset: int) -> int {
	at := offset
	for at > 0 && char_class(rune_before(s, at)) != .Word do at = previous_char(s, at)
	for at > 0 && char_class(rune_before(s, at)) == .Word do at = previous_char(s, at)
	return at
}

// Where the caret goes to move a word right: the end of the word after it on macOS,
// the start of the next word on Windows and Linux.
word_right :: proc(s: string, offset: int, platform := PLATFORM) -> int {
	at := offset
	if platform == .Mac {
		for at < len(s) && char_class(rune_at(s, at)) != .Word do at = next_char(s, at)
		for at < len(s) && char_class(rune_at(s, at)) == .Word do at = next_char(s, at)
	} else {
		for at < len(s) && char_class(rune_at(s, at)) == .Word do at = next_char(s, at)
		for at < len(s) && char_class(rune_at(s, at)) != .Word do at = next_char(s, at)
	}
	return at
}

// What a key does to the text being edited, as the system's text fields do; false
// for a key that is not for editing, which the field leaves to others. changed is
// true when the text changed.
edit_key :: proc(
	e: ^Text_Edit,
	press: Key_Press,
	clipboard: Clipboard,
	platform := PLATFORM,
) -> (
	handled, changed: bool,
) {
	s := edit_text(e)
	m := press.modifiers
	shift := .Shift in m
	command := m - {.Shift} == (platform == .Mac ? Modifiers{.Super} : Modifiers{.Control})
	word := m - {.Shift} == (platform == .Mac ? Modifiers{.Alt} : Modifiers{.Control})
	plain := m - {.Shift} == {}
	before := strings.clone(s, context.temp_allocator)
	#partial switch press.key {
	case .Left:
		switch {
		case !shift && has_selection(e) && plain:
			edit_move(e, min(e.caret, e.anchor))
		case platform == .Mac && command:
			edit_move(e, 0, shift)
		case word:
			edit_move(e, word_left(s, e.caret), shift)
		case plain:
			edit_move(e, previous_char(s, e.caret), shift)
		case:
			return
		}
	case .Right:
		switch {
		case !shift && has_selection(e) && plain:
			edit_move(e, max(e.caret, e.anchor))
		case platform == .Mac && command:
			edit_move(e, len(s), shift)
		case word:
			edit_move(e, word_right(s, e.caret, platform), shift)
		case plain:
			edit_move(e, next_char(s, e.caret), shift)
		case:
			return
		}
	case .Home, .Up:
		edit_move(e, 0, shift)
	case .End, .Down:
		edit_move(e, len(s), shift)
	case .Backspace:
		switch {
		case has_selection(e):
			edit_delete_to(e, e.caret)
		case platform == .Mac && command:
			edit_delete_to(e, 0)
		case word:
			edit_delete_to(e, word_left(s, e.caret))
		case:
			edit_delete_to(e, previous_char(s, e.caret))
		}
	case .Delete:
		switch {
		case has_selection(e):
			edit_delete_to(e, e.caret)
		case word:
			edit_delete_to(e, word_right(s, e.caret, platform))
		case:
			edit_delete_to(e, next_char(s, e.caret))
		}
	case .A:
		if !command || shift do return
		edit_select_all(e)
	case .C, .X:
		if !command || shift do return
		if has_selection(e) && clipboard.set != nil do clipboard.set(clipboard.data, selected_text(e))
		if press.key == .X do edit_delete_to(e, e.caret)
	case .V:
		if !command || shift || clipboard.get == nil do return
		edit_insert(e, clipboard.get(clipboard.data, context.temp_allocator))
		e.last = .None
	case .Z:
		if !command do return
		changed = shift ? edit_redo(e) : edit_undo(e)
		return true, changed
	case .Y:
		if !command || platform == .Mac do return
		return true, edit_redo(e)
	case:
		return
	}
	return true, edit_text(e) != before
}

// Where the text of a field goes to and comes from on copy and paste: the system's
// clipboard in the app, a string in tests.
Clipboard :: struct {
	data: rawptr,
	// The clipboard's text, allocated with allocator.
	get:  proc(data: rawptr, allocator: runtime.Allocator) -> string,
	set:  proc(data: rawptr, text: string),
}

@(private = "file")
Char_Class :: enum u8 {
	Word,
	Space,
	Punctuation,
}

@(private = "file")
char_class :: proc(r: rune) -> Char_Class {
	switch {
	case unicode.is_space(r):
		return .Space
	case unicode.is_letter(r), unicode.is_digit(r), r == '_', r == '\'', unicode.is_combining(r):
		return .Word
	}
	return .Punctuation
}

@(private = "file")
rune_at :: proc(s: string, offset: int) -> rune {
	r, _ := utf8.decode_rune_in_string(s[offset:])
	return r
}

@(private = "file")
rune_before :: proc(s: string, offset: int) -> rune {
	return rune_at(s, previous_char(s, offset))
}

@(private = "file")
delete_selection :: proc(e: ^Text_Edit) {
	if !has_selection(e) do return
	from, to := min(e.caret, e.anchor), max(e.caret, e.anchor)
	remove_range(&e.buffer, from, to)
	e.caret, e.anchor = from, from
}

// Keeps the text as it is before a change of kind, unless the change goes on with
// the last one: typing a word, deleting several characters.
@(private = "file")
remember :: proc(e: ^Text_Edit, kind: Edit_Kind) {
	if e.last != kind || len(e.undo) == 0 {
		append(
			&e.undo,
			Edit_Step{strings.clone(edit_text(e), e.buffer.allocator), e.caret, e.anchor},
		)
	}
	for &step in e.redo do delete(step.text, e.buffer.allocator)
	clear(&e.redo)
	e.last = kind
}

// Puts step's text in place and gives back what was there.
@(private = "file")
swap :: proc(e: ^Text_Edit, step: Edit_Step) -> Edit_Step {
	current := Edit_Step{strings.clone(edit_text(e), e.buffer.allocator), e.caret, e.anchor}
	clear(&e.buffer)
	append(&e.buffer, step.text)
	e.caret, e.anchor = step.caret, step.anchor
	delete(step.text, e.buffer.allocator)
	e.last = .None
	return current
}

@(private = "file")
clear_history :: proc(e: ^Text_Edit) {
	for &step in e.undo do delete(step.text, e.buffer.allocator)
	for &step in e.redo do delete(step.text, e.buffer.allocator)
	clear(&e.undo)
	clear(&e.redo)
}
