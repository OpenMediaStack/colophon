package ui

// How far an area has scrolled, in points: the screen keeps it between frames.
Scroll :: struct {
	offset: [2]f32,
}

// The width of a scroll bar, drawn over the edge of the content it scrolls.
SCROLL_BAR :: 10
@(private = "file")
THUMB_MIN :: 24

// Starts a scroll area at rect over content of that size: the wheel and the trackpad
// scroll it while the mouse is over it, the innermost area taking them, and Shift
// turns the wheel sideways. Draw the content at the origin it gives, clipped to rect,
// then call end_scroll, which draws the scroll bars.
begin_scroll :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	content: [2]f32,
	s: ^Scroll,
) -> (
	origin: [2]f32,
) {
	if mouse_over(ui, rect) do ui.scroll_hot_next = id
	if ui.scroll_hot == id {
		wheel := ui.input.wheel
		if .Shift in ui.input.modifiers && wheel.x == 0 do wheel = {wheel.y, 0}
		s.offset += wheel
	}
	clamp_scroll(s, rect, content)
	push_clip(ui.renderer, rect)
	return {rect.x - s.offset.x, rect.y - s.offset.y}
}

// Ends a scroll area: its scroll bars, where the content does not fit, which a drag of
// the thumb or a click on the track moves.
end_scroll :: proc(ui: ^Ui, id: Widget_Id, rect: Rect, content: [2]f32, s: ^Scroll) {
	pop_clip(ui.renderer)
	for axis in 0 ..< 2 {
		if content[axis] > rect_size(rect)[axis] do scroll_bar(ui, child_id(id, "scroll bar", axis), rect, content, s, axis)
	}
	clamp_scroll(s, rect, content)
}

// Scrolls the least that shows the span from start to start + length along axis, in a
// view of size view.
scroll_into_view :: proc(s: ^Scroll, start, length, view: f32, axis := 1) {
	if start < s.offset[axis] do s.offset[axis] = start
	if start + length > s.offset[axis] + view do s.offset[axis] = start + length - view
}

@(private = "file")
rect_size :: proc(r: Rect) -> [2]f32 {
	return {r.w, r.h}
}

@(private = "file")
clamp_scroll :: proc(s: ^Scroll, rect: Rect, content: [2]f32) {
	size := rect_size(rect)
	for axis in 0 ..< 2 do s.offset[axis] = clamp(s.offset[axis], 0, max(content[axis] - size[axis], 0))
}

// The scroll bar along axis, 0 across and 1 down.
@(private = "file")
scroll_bar :: proc(ui: ^Ui, id: Widget_Id, rect: Rect, content: [2]f32, s: ^Scroll, axis: int) {
	vertical := axis == 1
	track :=
		vertical ? Rect{rect.x + rect.w - SCROLL_BAR, rect.y, SCROLL_BAR, rect.h} : Rect{rect.x, rect.y + rect.h - SCROLL_BAR, rect.w, SCROLL_BAR}
	length := vertical ? track.h : track.w
	view := rect_size(rect)[axis]
	most := content[axis] - view
	thumb_length := max(view / content[axis] * length, THUMB_MIN)
	travel := max(length - thumb_length, 1)
	pointer := (vertical ? ui.input.mouse.y - track.y : ui.input.mouse.x - track.x)
	interaction := interact(ui, id, track)
	thumb_at := s.offset[axis] / most * travel
	if .Pressed in interaction {
		// A click beside the thumb brings it under the pointer, then the drag goes on.
		if pointer < thumb_at || pointer > thumb_at + thumb_length {
			s.offset[axis] = clamp((pointer - thumb_length / 2) / travel * most, 0, most)
		}
		ui.drag_from = s.offset[axis]
	} else if .Held in interaction {
		pressed := vertical ? ui.press_mouse.y - track.y : ui.press_mouse.x - track.x
		s.offset[axis] = clamp(ui.drag_from + (pointer - pressed) / travel * most, 0, most)
	}
	thumb_at = s.offset[axis] / most * travel
	thumb :=
		vertical ? Rect{track.x + 2, track.y + thumb_at, SCROLL_BAR - 4, thumb_length} : Rect{track.x + thumb_at, track.y + 2, thumb_length, SCROLL_BAR - 4}
	states: Button_States
	if .Hovered in interaction do states += {.Hovered}
	if .Held in interaction do states += {.Pressed}
	draw_scroll_thumb(ui.renderer, ui.theme, thumb, states)
	label := vertical ? "Vertical scroll bar" : "Horizontal scroll bar"
	declare(ui, {id = id, role = .Slider, label = label, rect = track, value = ""})
}

// Draws a scroll bar's thumb in states, without the Ui.
draw_scroll_thumb :: proc(r: ^Renderer, th: Theme, thumb: Rect, states: Button_States) {
	active := .Hovered in states || .Pressed in states
	fill_rect(r, thumb, active ? th.text_tertiary : th.border_strong, 3)
}
