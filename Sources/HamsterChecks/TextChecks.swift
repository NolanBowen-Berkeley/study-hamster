import Foundation
import HamsterCore

func runDurationParserChecks() {
    section("DurationParser accepted forms") {
        let accepted: [(String, TimeInterval)] = [
            // Every form listed in the spec.
            ("90", 5400),
            ("90m", 5400),
            ("90 min", 5400),
            ("90 minutes", 5400),
            ("45mins", 2700),
            ("1h", 3600),
            ("1 h", 3600),
            ("1hr", 3600),
            ("2 hours", 7200),
            ("1h30", 5400),
            ("1h30m", 5400),
            ("1h 30m", 5400),
            ("1 hour 30 minutes", 5400),
            ("1:30", 5400),
            ("1.5h", 5400),
            ("1.5 hours", 5400),
            ("0.5h", 1800),
            ("an hour", 3600),
            ("a hour", 3600),
            ("half an hour", 1800),
            ("half hour", 1800),
            ("1 and a half hours", 5400),
            ("an hour and a half", 5400),
            ("90s", 90),
            ("90 sec", 90),
            ("90 seconds", 90),
            ("1h 30m 20s", 5420),
            ("1 1/2 hours", 5400),
            // Decimal comma.
            ("1,5h", 5400),
            ("1,5 hours", 5400),
            ("0,25 h", 900),
            // More natural variants.
            ("25", 1500),
            ("1", 60),
            ("0.1", 6),
            ("1 minute", 60),
            ("1 min", 60),
            ("30 secs", 30),
            ("1 second", 1),
            ("2hrs", 7200),
            ("1 hr 30 mins", 5400),
            ("2h 5m", 7500),
            ("1hour30min", 5400),
            ("1 hour and 30 minutes", 5400),
            ("1 hour, 30 minutes", 5400),
            ("1 hour 30", 5400),
            ("10m30s", 630),
            ("10m30", 630),
            ("an hour and a minute", 3660),
            ("an hour and half", 5400),
            ("1 hour and a half", 5400),
            ("2 and a half hours", 9000),
            ("one hour", 3600),
            ("a half hour", 1800),
            ("half a minute", 30),
            ("1½ hours", 5400),
            ("1½h", 5400),
            ("½ h", 1800),
            ("1/2 h", 1800),
            ("3/4 hour", 2700),
            (".5h", 1800),
            ("1.25 h", 4500),
            ("90 min.", 5400),
            ("0:45", 2700),
            ("01:30", 5400),
            ("1:30:15", 5415),
            ("2:00", 7200),
            // The maximum itself is allowed.
            ("12h", 43200),
            ("720", 43200),
            ("12:00", 43200),
            ("11h 59m 59s", 43199),
        ]
        for (text, expected) in accepted {
            checkEqual(DurationParser.parse(text), expected, "parse(\(text.debugDescription))")
        }
    }

    section("DurationParser case and whitespace") {
        let variants: [(String, TimeInterval)] = [
            ("  90 MIN  ", 5400),
            ("1H30M", 5400),
            ("\t2 Hours\n", 7200),
            ("An Hour And A Half", 5400),
            ("HALF AN HOUR", 1800),
            ("1  h   30  m", 5400),
            ("  45  ", 2700),
            ("1 HR", 3600),
            ("90Sec", 90),
            (" 1:30 ", 5400),
            ("1,5 H", 5400),
        ]
        for (text, expected) in variants {
            checkEqual(DurationParser.parse(text), expected, "parse(\(text.debugDescription))")
        }
    }

    section("DurationParser rejected forms") {
        let rejected = [
            "", "   ", "\n", "abc", "0", "0m", "0h 0m", "0:00", "00:00", "-5", "-1h", "+5", "1:75", "1:5", "1:30:75",
            ":30", "1:", "1:30:", "13h", "12h 1s", "721", "12:01", "100:00", "999999999999999999999999",
            "nan", "NaN", "inf", "infinity", "-inf", "1e5", "h", "min", "hour", "and", "a", "an", "half", "one",
            "1 hour and", "and 5", "5 5", "1 1", "1h 1h", "30m 1h", "1h75", "90 sec 5", "1/0 h", "1.2.3", ".",
            "1 / 2 h", "$5", "5 bananas", "10 minutes ago", "0.001", "half and a half hours", "1h30m20s10",
        ]
        for text in rejected {
            checkEqual(DurationParser.parse(text), nil, "parse(\(text.debugDescription)) should be rejected")
        }
        check(DurationParser.maximum == 43200, "maximum is 12 h")
    }
}

func runTimeFormatChecks() {
    section("TimeFormat.clock") {
        let table: [(TimeInterval, String)] = [
            (0, "0:00"),
            (0.2, "0:01"),
            (1, "0:01"),
            (9, "0:09"),
            (59, "0:59"),
            (59.2, "1:00"),
            (60, "1:00"),
            (61, "1:01"),
            (245, "4:05"),
            (1499, "24:59"),
            (1500, "25:00"),
            // Floating-point noise from Date arithmetic must not show an extra second.
            (1500.000_000_1, "25:00"),
            (3599, "59:59"),
            (3599.5, "1:00:00"),
            (3600, "1:00:00"),
            (3723, "1:02:03"),
            (7200, "2:00:00"),
            (43200, "12:00:00"),
            (-5, "0:00"),
            (-0.5, "0:00"),
            (.nan, "0:00"),
            (.infinity, "0:00"),
            (-.infinity, "0:00"),
        ]
        for (seconds, expected) in table {
            checkEqual(TimeFormat.clock(seconds), expected, "clock(\(seconds))")
        }
        check(!TimeFormat.clock(1e300).isEmpty, "clock(1e300) formats without crashing")
    }

    section("TimeFormat.humanDuration") {
        let table: [(TimeInterval, String)] = [
            (0, "0 sec"),
            (0.2, "0 sec"),
            (1, "1 sec"),
            (45, "45 sec"),
            (59.2, "59 sec"),
            (59.6, "1 min"),
            (60, "1 min"),
            (61, "1 min"),
            (89, "1 min"),
            (90, "2 min"),
            (1500, "25 min"),
            (3599.5, "1 h"),
            (3600, "1 h"),
            (3723, "1 h 2 min"),
            (5400, "1 h 30 min"),
            (7200, "2 h"),
            (7500, "2 h 5 min"),
            (43200, "12 h"),
            (-5, "0 sec"),
            (.nan, "0 sec"),
            (.infinity, "0 sec"),
            (-.infinity, "0 sec"),
        ]
        for (seconds, expected) in table {
            checkEqual(TimeFormat.humanDuration(seconds), expected, "humanDuration(\(seconds))")
        }
        check(!TimeFormat.humanDuration(1e300).isEmpty, "humanDuration(1e300) formats without crashing")
    }
}
