import Foundation
import Testing
@testable import SparkPlugCore

@Suite struct TimeFormatTests {
    let us = TimeFormat(calendar: nyCalendar, locale: Locale(identifier: "en_US"))
    let uk = TimeFormat(calendar: nyCalendar, locale: Locale(identifier: "en_GB"))

    @Test(arguments: [
        (9.0, "9 AM"), (9.5, "9:30 AM"), (12.0, "12 PM"), (0.25, "12:15 AM"), (13.25, "1:15 PM"), (23.75, "11:45 PM"),
    ])
    func twelveHourTimes(hour: Double, expected: String) {
        #expect(us.time(oct20(hour)) == expected)
    }

    @Test func twentyFourHourLocalesUseHoursAndMinutes() {
        #expect(!uk.uses12Hour)
        #expect(uk.time(oct20(9.5)) == "09:30")
        #expect(uk.range(oct20(13), oct20(14.25)) == "13:00 – 14:15")
        #expect(uk.hourLabel(8) == "08:00")
    }

    @Test func rangesDropTheFirstSuffixOnlyWhenBothHalvesMatch() {
        #expect(us.range(oct20(9.5), oct20(11)) == "9:30 – 11 AM")
        #expect(us.range(oct20(12.5), oct20(13.25)) == "12:30 – 1:15 PM")
        #expect(us.range(oct20(11.5), oct20(12.5)) == "11:30 AM – 12:30 PM")
    }

    @Test(arguments: [(8, "8 AM"), (12, "12 PM"), (18, "6 PM"), (0, "12 AM"), (24, "12 AM")])
    func hourLabels(hour: Int, expected: String) {
        #expect(us.hourLabel(hour) == expected)
    }

    @Test(arguments: [(10, "10m"), (45, "45m"), (60, "1h"), (90, "1h 30m"), (120, "2h"), (135, "2h 15m")])
    func durations(minutes: Int, expected: String) {
        #expect(TimeFormat.duration(minutes: minutes) == expected)
    }

    @Test(arguments: [(1188, "19:48"), (59, "0:59"), (3600, "1:00:00"), (3723, "1:02:03"), (-5, "0:00")])
    func countdowns(seconds: Int, expected: String) {
        #expect(TimeFormat.countdown(seconds: seconds) == expected)
    }

    @Test func dayAndWeekTitles() {
        #expect(us.dayTitle(oct20(10)) == "Tuesday, October 20")
        #expect(us.weekTitle(from: oct20(0, day: 19), to: oct20(0, day: 23)) == "October 19 – 23")
        #expect(us.weekday(oct20(10)) == "TUE")
        #expect(us.shortDate(oct20(10)) == "Oct 20")
    }
}
