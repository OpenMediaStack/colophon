package library_tests

import "core:testing"

import lib ".."

@(test)
the_policy_chooses_the_versions_to_write :: proc(t: ^testing.T) {
	with_id3v1 := lib.Tag_Formats {
		id3v2 = .V2_4,
		id3v1 = .V1_1,
	}
	without_id3v1 := lib.Tag_Formats {
		id3v2 = .V2_4,
	}
	policy :: proc(id3v1: lib.Id3v1_Policy) -> lib.Write_Policy {
		return {.V2_3, id3v1}
	}
	testing.expect_value(
		t,
		lib.versions_following(policy(.Keep), with_id3v1),
		lib.Tag_Versions{.V2_3, .V1_1},
	)
	testing.expect_value(t, lib.versions_following(policy(.Keep), without_id3v1).id3v1, nil)
	testing.expect_value(
		t,
		lib.versions_following(policy(.Always), without_id3v1).id3v1,
		Maybe(lib.Id3v1_Version)(lib.Id3v1_Version.V1_1),
	)
	testing.expect_value(t, lib.versions_following(policy(.Never), with_id3v1).id3v1, nil)
}

@(test)
an_id3v1_1_tag_without_a_track_reads_as_id3v1_0 :: proc(t: ^testing.T) {
	versions := lib.Tag_Versions{.V2_4, .V1_1}
	formats := lib.Tag_Formats {
		ape = true,
	}
	for track in ([]Maybe(int){nil, 0, 256}) {
		tags := lib.Tags {
			track = track,
		}
		after := lib.formats_after_write(formats, &tags, versions)
		testing.expectf(t, after.id3v1 == .V1_0, "track %v: %v", track, after)
		testing.expect(t, after.ape)
	}
	tags := lib.Tags {
		track = 3,
	}
	testing.expect_value(
		t,
		lib.formats_after_write(formats, &tags, versions),
		lib.Tag_Formats{id3v2 = .V2_4, id3v1 = .V1_1, ape = true},
	)
}
