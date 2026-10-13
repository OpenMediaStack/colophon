package library_tests

import "core:testing"

import lib ".."

@(test)
values_that_fit_id3v1_lose_nothing :: proc(t: ^testing.T) {
	tags := lib.Tags {
		title   = "Paper Satellites",
		artist  = "Björk",
		year    = 2019,
		track   = 3,
		comment = "Exactly twenty-eight bytes!!",
		genre   = "folk",
	}
	testing.expect_value(t, lib.id3v1_losses(&tags, .V1_1), lib.Id3v1_Losses{})
}

@(test)
values_too_long_or_outside_latin1_are_lost :: proc(t: ^testing.T) {
	tags := lib.Tags {
		title   = "A title longer than thirty characters",
		artist  = "坂本龍一",
		track   = 3,
		comment = "Twenty-nine bytes, one too many",
		genre   = "Hyperpop",
	}
	testing.expect_value(
		t,
		lib.id3v1_losses(&tags, .V1_1),
		lib.Id3v1_Losses{.Title, .Artist, .Comment, .Genre},
	)
}

@(test)
a_comment_without_a_track_keeps_30_characters :: proc(t: ^testing.T) {
	with_track := lib.Tags {
		comment = "Thirty bytes, the whole field.",
		track   = 1,
	}
	without := lib.Tags {
		comment = "Thirty bytes, the whole field.",
	}
	testing.expect_value(t, lib.id3v1_losses(&with_track, .V1_1), lib.Id3v1_Losses{.Comment})
	testing.expect_value(t, lib.id3v1_losses(&without, .V1_1), lib.Id3v1_Losses{})
}

@(test)
id3v1_0_loses_the_track_and_keeps_30_characters_of_comment :: proc(t: ^testing.T) {
	tags := lib.Tags {
		comment = "Thirty bytes, the whole field.",
		track   = 1,
	}
	testing.expect_value(t, lib.id3v1_losses(&tags, .V1_0), lib.Id3v1_Losses{.Track})
}

@(test)
a_year_of_five_digits_is_lost :: proc(t: ^testing.T) {
	tags := lib.Tags {
		year = 10000,
	}
	testing.expect_value(t, lib.id3v1_losses(&tags, .V1_1), lib.Id3v1_Losses{.Year})
}
