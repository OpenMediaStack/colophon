package ui

// A rectangle in points: the unit of layout, which the renderer turns into pixels.
Rect :: struct {
	x, y, w, h: f32,
}

rect_contains :: proc(r: Rect, p: [2]f32) -> bool {
	return p.x >= r.x && p.y >= r.y && p.x < r.x + r.w && p.y < r.y + r.h
}

// The part two rectangles share, empty when they do not touch.
rect_intersect :: proc(a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(a.x + a.w, b.x + b.w)
	y1 := min(a.y + a.h, b.y + b.h)
	return {x0, y0, max(x1 - x0, 0), max(y1 - y0, 0)}
}

rect_inset :: proc(r: Rect, dx, dy: f32) -> Rect {
	return {r.x + dx, r.y + dy, max(r.w - 2 * dx, 0), max(r.h - 2 * dy, 0)}
}

// Takes a strip of width w off the left of r, and returns it.
cut_left :: proc(r: ^Rect, w: f32) -> Rect {
	cut := Rect{r.x, r.y, clamp(w, 0, r.w), r.h}
	r.x += cut.w
	r.w -= cut.w
	return cut
}

// Takes a strip of width w off the right of r, and returns it.
cut_right :: proc(r: ^Rect, w: f32) -> Rect {
	width := clamp(w, 0, r.w)
	r.w -= width
	return {r.x + r.w, r.y, width, r.h}
}

// Takes a strip of height h off the top of r, and returns it.
cut_top :: proc(r: ^Rect, h: f32) -> Rect {
	cut := Rect{r.x, r.y, r.w, clamp(h, 0, r.h)}
	r.y += cut.h
	r.h -= cut.h
	return cut
}

// Takes a strip of height h off the bottom of r, and returns it.
cut_bottom :: proc(r: ^Rect, h: f32) -> Rect {
	height := clamp(h, 0, r.h)
	r.h -= height
	return {r.x, r.y + r.h, r.w, height}
}
