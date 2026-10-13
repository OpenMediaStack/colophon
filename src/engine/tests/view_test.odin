package engine_tests

import "base:runtime"
import "core:reflect"
import "core:testing"

import "../../engine"

@(test)
both_panels_are_visible_at_start :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	testing.expect(t, e.view.sidebar_visible)
	testing.expect(t, e.view.inspector_visible)
}

@(test)
toggling_a_panel_leaves_the_other_alone_and_twice_restores_it :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Toggle_Sidebar{})
	testing.expect(t, !e.view.sidebar_visible)
	testing.expect(t, e.view.inspector_visible)
	engine.execute(&e, engine.Toggle_Inspector{})
	engine.execute(&e, engine.Toggle_Sidebar{})
	testing.expect(t, e.view.sidebar_visible)
	testing.expect(t, !e.view.inspector_visible)
	engine.execute(&e, engine.Toggle_Inspector{})
	testing.expect_value(t, e.view, engine.DEFAULT_VIEW)
}

@(test)
the_table_shows_the_columns_of_the_mockup_but_the_bitrate_at_start :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	testing.expect_value(t, e.view.columns, engine.Columns{.Artist, .Album, .Year, .Genre, .Time})
}

@(test)
toggling_a_column_shows_or_hides_it_alone :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Toggle_Column{.Tags})
	engine.execute(&e, engine.Toggle_Column{.Genre})
	testing.expect_value(t, e.view.columns, engine.Columns{.Artist, .Album, .Year, .Time, .Tags})
}

@(test)
the_table_shares_its_width_until_a_column_is_resized :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	testing.expect_value(t, e.view.column_widths, nil)
	widths := #partial engine.Column_Widths {
		.Title  = 300,
		.Artist = 180,
	}
	engine.execute(&e, engine.Resize_Columns{widths})
	testing.expect_value(t, e.view.column_widths, widths)
}

@(test)
resetting_the_columns_brings_back_those_of_the_mockup :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Toggle_Column{.Tags})
	engine.execute(&e, engine.Toggle_Column{.Artist})
	engine.execute(&e, engine.Resize_Columns{})
	engine.execute(&e, engine.Move_Column{.Genre, engine.Table_Column.Title})
	testing.expect_value(t, e.view.column_order[0], engine.Table_Column.Genre)
	engine.execute(&e, engine.Reset_Columns{})
	testing.expect_value(t, e.view, engine.DEFAULT_VIEW)
}

@(test)
developer_mode_is_off_until_turned_on :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	testing.expect(t, !e.view.developer_mode)
	engine.execute(&e, engine.Toggle_Developer_Mode{})
	testing.expect(t, e.view.developer_mode)
}

@(test)
the_next_launch_starts_from_the_preferences :: proc(t: ^testing.T) {
	e, next: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.init(&next)
	defer engine.destroy(&next)
	engine.execute(&e, engine.Toggle_Sidebar{})
	engine.execute(&e, engine.Toggle_Column{.Tags})
	engine.execute(&e, engine.Set_Volume{35})
	engine.execute(&e, engine.Resize_Window{{1440, 900}})
	engine.execute(&e, engine.Set_Write_Policy{{.V2_3, .Never}})

	engine.restore(&next, engine.preferences(&e))

	testing.expect_value(t, engine.preferences(&next), engine.preferences(&e))
	testing.expect(t, !next.view.sidebar_visible)
	testing.expect(t, .Tags in next.view.columns)
	testing.expect(t, abs(next.playback.volume - 0.35) < 1e-6)
	testing.expect_value(t, next.edits.policy.id3v1, .Never)
}

@(test)
every_command_has_its_own_id :: proc(t: ^testing.T) {
	seen := make(map[string]typeid, context.temp_allocator)
	defer free_all(context.temp_allocator)
	info := runtime.type_info_base(type_info_of(engine.Command))
	variants := info.variant.(runtime.Type_Info_Union).variants
	for variant in variants {
		command: engine.Command
		reflect.set_union_variant_type_info(command, variant)
		id := engine.command_id(command)
		testing.expectf(t, id != "", "%v has no id", variant.id)
		other, taken := seen[id]
		testing.expectf(t, !taken, "%v and %v share %q", other, variant.id, id)
		seen[id] = variant.id
	}
	testing.expect(t, len(variants) >= 30)
}
