#!/bin/bash
# Regenerates Colophon's fixtures and what ffprobe reads in them. Run from anywhere: ./testdata/make.sh
#
# The tag fixtures hold 0.1 s of generated silence, the audio ones 1 s of a generated sine, so no
# fixture carries third party content. The bitexact flags keep ffmpeg's version out of the files.
# Each fixture.mp3 that ffprobe can read gets a fixture.ffprobe next to it (-of flat), which the
# parity tests compare with what Colophon reads.
#
# ffmpeg writes ID3v1 bytes as given: UTF-8 text stays UTF-8, a raw byte stays raw.
# With -id3v2_version 0, ffmpeg only fills ID3v1 from ID3v2 frame names
# (TIT2, TPE1, TALB, TYER, TRCK, TCON) plus "comment" for the comment field.
#
# ID3v1 layout (last 128 bytes): "TAG", title 30, artist 30, album 30, year 4,
# comment 30, genre 1. In v1.1, comment byte 28 (offset 125) is 0 and byte 29
# (offset 126) is the track number.

set -euo pipefail
cd "$(dirname "$0")"

rm -f ./*.mp3 ./*.ffprobe

# The bitexact flags go after the input: before it, they would only apply to reading the input.
silence=(-v error -y -f lavfi -i anullsrc=r=44100:cl=mono -t 0.1
	-fflags +bitexact -flags:a +bitexact -write_xing 0)
sine=(-v error -y -f lavfi -i sine=frequency=440:duration=1
	-fflags +bitexact -flags:a +bitexact)
v1_only=(-id3v2_version 0 -write_id3v1 1)
no_tags=(-id3v2_version 0 -write_id3v1 0)
every_field=(
	-metadata title="Paper Satellites"
	-metadata artist="Marlowe Kite"
	-metadata album_artist="Various Artists"
	-metadata album="Small Hours"
	-metadata date=2019
	-metadata track=3/12
	-metadata disc=1/2
	-metadata genre=Folk
	-metadata comment="Recorded in one take."
)

# no_tag.mp3: audio only, no tag at all.
# Expect: no tag format, every field empty.
ffmpeg "${silence[@]}" "${no_tags[@]}" no_tag.mp3

# v23_full.mp3: ID3v2.3 with every field Colophon shows. ffmpeg writes the comment in a TXXX frame
# described "comment", not in a COMM frame.
# Expect: formats ID3v2.3, title "Paper Satellites", artist "Marlowe Kite",
#   album artist "Various Artists", album "Small Hours", year 2019, track 3 of 12,
#   disc 1 of 2, genre "Folk", comment "Recorded in one take.".
ffmpeg "${silence[@]}" -id3v2_version 3 -write_id3v1 0 "${every_field[@]}" v23_full.mp3

# v24_full.mp3: the same fields in ID3v2.4, where the year is a TDRC timestamp.
# Expect: formats ID3v2.4, the same values as v23_full.mp3.
ffmpeg "${silence[@]}" -id3v2_version 4 -write_id3v1 0 "${every_field[@]}" v24_full.mp3

# v23_comm.mp3: an ID3v2.3 tag written byte by byte before the audio of no_tag.mp3, since ffmpeg
# cannot write a COMM frame. Frame sizes are plain 32-bit numbers in ID3v2.3, the tag size is
# syncsafe (7 bits per byte). TIT2 is 10 + 18 bytes, COMM 10 + 26 (Latin-1, language "eng",
# empty description), so the tag holds 64 bytes (0x40).
# Expect: formats ID3v2.3, title "A real COMM frame", comment "Recorded in one take.".
{
	printf 'ID3\x03\x00\x00\x00\x00\x00\x40'
	printf 'TIT2\x00\x00\x00\x12\x00\x00\x00A real COMM frame'
	printf 'COMM\x00\x00\x00\x1a\x00\x00\x00eng\x00Recorded in one take.'
	cat no_tag.mp3
} >v23_comm.mp3

# v23_v1_long_title.mp3: ID3v2.3 and ID3v1.1 written from the same values, with a title
# longer than ID3v1's 30 bytes.
# Expect: formats ID3v2.3 then ID3v1.1, title "A title longer than thirty characters" in full,
#   since the values come from ID3v2 (ID3v1 holds "A title longer than thirty cha").
ffmpeg "${silence[@]}" -id3v2_version 3 -write_id3v1 1 \
	-metadata title="A title longer than thirty characters" \
	-metadata artist="Marlowe Kite" \
	-metadata track=3 \
	v23_v1_long_title.mp3

# v23_unicode.mp3: text outside Latin-1, which ID3v2.3 stores in UTF-16.
# Expect: formats ID3v2.3, title "Café", artist "坂本龍一", album "Ελληνικά".
ffmpeg "${silence[@]}" -id3v2_version 3 -write_id3v1 0 \
	-metadata title="Café" \
	-metadata artist="坂本龍一" \
	-metadata album="Ελληνικά" \
	v23_unicode.mp3

# v24_unicode.mp3: the same text in ID3v2.4, which stores it in UTF-8.
# Expect: formats ID3v2.4, the same values as v23_unicode.mp3.
ffmpeg "${silence[@]}" -id3v2_version 4 -write_id3v1 0 \
	-metadata title="Café" \
	-metadata artist="坂本龍一" \
	-metadata album="Ελληνικά" \
	v24_unicode.mp3

# v1_0_ascii.mp3: ID3v1.0, every field filled, comment uses all 30 bytes.
# Offset 125 is not 0, so this is v1.0 and there is no track number.
# Expect: formats ID3v1.0, title "Plain ASCII title", artist "Plain ASCII artist",
#   album "Plain ASCII album", year 1999,
#   comment "A comment of exactly 30 bytes.", genre "Rock", no track.
ffmpeg "${silence[@]}" "${v1_only[@]}" \
	-metadata TIT2="Plain ASCII title" \
	-metadata TPE1="Plain ASCII artist" \
	-metadata TALB="Plain ASCII album" \
	-metadata TYER=1999 \
	-metadata comment="A comment of exactly 30 bytes." \
	-metadata TCON=Rock \
	v1_0_ascii.mp3

# v1_1_ascii.mp3: ID3v1.1, track number set, genre from the Winamp extension.
# Expect: formats ID3v1.1, title "Track seven", artist "Plain ASCII artist",
#   album "Plain ASCII album", year 2004, comment "Short comment",
#   track 7, genre "Folk-Rock" (number 81, Winamp extension).
ffmpeg "${silence[@]}" "${v1_only[@]}" \
	-metadata TIT2="Track seven" \
	-metadata TPE1="Plain ASCII artist" \
	-metadata TALB="Plain ASCII album" \
	-metadata TYER=2004 \
	-metadata comment="Short comment" \
	-metadata TRCK=7 \
	-metadata TCON=Folk-Rock \
	v1_1_ascii.mp3

# v1_latin1.mp3: ID3v1.0 text in ISO-8859-1, as the spec intends.
# Raw bytes: title 43 61 66 e9, artist 42 6a f6 72 6b, album 53 65 f1 6f 72.
# Expect: title "Café", artist "Björk", album "Señor", comment "Latin-1", no genre.
ffmpeg "${silence[@]}" "${v1_only[@]}" \
	-metadata TIT2=$'Caf\xe9' \
	-metadata TPE1=$'Bj\xf6rk' \
	-metadata TALB=$'Se\xf1or' \
	-metadata comment="Latin-1" \
	v1_latin1.mp3

# v1_utf8.mp3: the same text in UTF-8, as ffmpeg writes it, against the spec.
# Raw bytes: title 43 61 66 c3 a9, artist 42 6a c3 b6 72 6b, album 53 65 c3 b1 6f 72.
# Expect: UTF-8 is read as UTF-8 when its bytes are valid, as ffprobe does: the same values as
#   v1_latin1.mp3, comment "UTF-8".
ffmpeg "${silence[@]}" "${v1_only[@]}" \
	-metadata TIT2="Café" \
	-metadata TPE1="Björk" \
	-metadata TALB="Señor" \
	-metadata comment="UTF-8" \
	v1_utf8.mp3

# v1_utf8_cut.mp3: UTF-8 title cut by the 30 byte limit inside a character.
# The title given is 29 ASCII letters then "é" (c3 a9). Only c3 fits.
# Expect: title "ABCDEFGHIJKLMNOPQRSTUVWXYZabcÃ", artist "Cut in the middle", no panic.
ffmpeg "${silence[@]}" "${v1_only[@]}" \
	-metadata TIT2="ABCDEFGHIJKLMNOPQRSTUVWXYZabcé" \
	-metadata TPE1="Cut in the middle" \
	v1_utf8_cut.mp3

# v1_genre_out_of_range.mp3: genre byte 200, past the end of every genre list.
# ffmpeg cannot write it, so the last byte is patched.
# Expect: title "Unknown genre", no genre, no panic.
ffmpeg "${silence[@]}" "${v1_only[@]}" \
	-metadata TIT2="Unknown genre" \
	v1_genre_out_of_range.mp3
size=$(wc -c <v1_genre_out_of_range.mp3)
printf '\310' | dd of=v1_genre_out_of_range.mp3 bs=1 seek=$((size - 1)) conv=notrunc 2>/dev/null

# cbr_stereo.mp3: 1 s of a 440 Hz sine, constant 128 kbps, stereo, 44.1 kHz, no tag.
# Expect: about 1 s, 128 kbps, 44100 Hz, 2 channels.
ffmpeg "${sine[@]}" -ac 2 -ar 44100 -b:a 128k "${no_tags[@]}" cbr_stereo.mp3

# vbr_mono.mp3: the same sine, variable bitrate (LAME quality 6) with a Xing header, mono, 48 kHz.
# Expect: about 1 s, 48000 Hz, 1 channel, the average bitrate ffprobe reports.
ffmpeg "${sine[@]}" -ac 1 -ar 48000 -q:a 6 "${no_tags[@]}" vbr_mono.mp3

# tiny_tag.mp3: a 3 byte file that is only "TAG".
# Expect: an error, no panic.
printf 'TAG' >tiny_tag.mp3

for fixture in ./*.mp3; do
	probe="${fixture%.mp3}.ffprobe"
	if ! ffprobe -v error -show_format -show_streams -of flat "$fixture" >"$probe" 2>/dev/null; then
		rm -f "$probe"
	fi
done
