// Command-line checks for the framework-free core (validation rules + XLSX export).
// Run: ./Scripts/verify.sh core
import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ \(message) (line \(line))")
    }
}

let seoul = TimeZone(identifier: "Asia/Seoul")!
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = seoul
func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}
let formatter = KACFormatter(timeZone: seoul)

print("Formatter")
let e1 = LogEntry(start: date(2026, 9, 1, 10, 0, 12), end: date(2026, 9, 1, 10, 50, 40), clientNames: ["홍길동"], kind: .paid)
check(formatter.dateText(e1) == "2026-09-01", "date text")
check(formatter.timeText(e1) == "10:00-10:50", "time text")
check(e1.recordedMinutes == 50, "minutes follow the written time range")
check(formatter.formatText(e1) == "1:1 대면", "format text 1:1")

let group = LogEntry(start: date(2026, 9, 2, 12, 0), end: date(2026, 9, 2, 14, 0), clientNames: ["가", "나", "다", "라"], groupSize: 6, kind: .paid, format: .remote)
check(formatter.clientText(group) == "가\n나\n다", "group lists 3 names")
check(formatter.formatText(group) == "1:6 비대면\n(총6명)", "group format text")

let ctc = LogEntry(start: date(2026, 9, 3, 13, 0), end: date(2026, 9, 3, 13, 50), clientNames: ["김코치"], kind: .coachTheCoach, ctcComposition: .oneOnOne, ctcLicenseNumber: "KPC01234")
check(ctc.recordedMinutes == 100, "1:1 coach-the-coach doubled")
check(formatter.clientText(ctc) == "김코치\n/KPC01234", "CTC client text")

print("Validation")
let free = LogEntry(start: date(2026, 9, 4, 9, 0), end: date(2026, 9, 4, 10, 0), clientNames: ["이몽룡"], kind: .free)
let okIssues = KACValidator.validate(entries: [e1, group, ctc, free], candidateName: "이현호", formatter: formatter)
check(okIssues.filter { $0.severity == .error }.isEmpty, "valid log has no errors: \(okIssues.map(\.message))")

let short = LogEntry(start: date(2026, 9, 5, 9, 0), end: date(2026, 9, 5, 9, 20), clientNames: ["홍길동"])
let sameDay1 = LogEntry(start: date(2026, 9, 6, 9, 0), end: date(2026, 9, 6, 10, 0), clientNames: ["홍길동"])
let sameDay2 = LogEntry(start: date(2026, 9, 6, 11, 0), end: date(2026, 9, 6, 12, 10), clientNames: ["홍 길동"])
let sameDay3 = LogEntry(start: date(2026, 9, 6, 13, 0), end: date(2026, 9, 6, 13, 30), clientNames: ["홍길동"])
let longCTC = LogEntry(start: date(2026, 9, 7, 9, 0), end: date(2026, 9, 7, 10, 30), clientNames: ["김코치"], kind: .coachTheCoach, ctcLicenseNumber: "KPC1")
let bad = KACValidator.validate(entries: [short, sameDay1, sameDay2, sameDay3, longCTC], candidateName: "", formatter: formatter)
func has(_ rule: Int, _ prefix: String) -> Bool { bad.contains { $0.rule == rule && $0.code.hasPrefix(prefix) } }
check(has(1, "candidate"), "missing candidate name")
check(has(2, "clients"), "fewer than 3 clients")
check(has(3, "length"), "session shorter than 30 minutes")
check(has(3, "sameDayCount"), "3 sessions with same client in one day")
check(has(3, "sameDayMinutes"), "same client over 120 minutes in one day")
check(has(6, "ctcDoubled"), "doubled CTC over 120 minutes")

print("Session length")
func lengthCodes(_ entry: LogEntry) -> [String] {
    KACValidator.validate(entry: entry, formatter: formatter).map(\.code)
}
let paid120 = LogEntry(start: date(2026, 9, 8, 9, 0), end: date(2026, 9, 8, 11, 0), clientNames: ["홍길동"])
let paid121 = LogEntry(start: date(2026, 9, 8, 9, 0), end: date(2026, 9, 8, 11, 1), clientNames: ["홍길동"])
let paid30 = LogEntry(start: date(2026, 9, 8, 9, 0), end: date(2026, 9, 8, 9, 30), clientNames: ["홍길동"])
let paid29 = LogEntry(start: date(2026, 9, 8, 9, 0), end: date(2026, 9, 8, 9, 29), clientNames: ["홍길동"])
check(!lengthCodes(paid120).contains("length"), "120 minutes is allowed")
check(lengthCodes(paid121).contains("length"), "121 minutes is an error")
check(!lengthCodes(paid30).contains("length"), "30 minutes is allowed")
check(lengthCodes(paid29).contains("length"), "29 minutes is an error")

let ctc60 = LogEntry(start: date(2026, 9, 8, 13, 0), end: date(2026, 9, 8, 14, 0), clientNames: ["김코치"], kind: .coachTheCoach, ctcComposition: .oneOnOne, ctcLicenseNumber: "KPC1")
let ctc61 = LogEntry(start: date(2026, 9, 8, 13, 0), end: date(2026, 9, 8, 14, 1), clientNames: ["김코치"], kind: .coachTheCoach, ctcComposition: .oneOnTwo, ctcLicenseNumber: "KPC1")
let ctc29 = LogEntry(start: date(2026, 9, 8, 13, 0), end: date(2026, 9, 8, 13, 29), clientNames: ["김코치"], kind: .coachTheCoach, ctcComposition: .oneOnOne, ctcLicenseNumber: "KPC1")
let ctcGroup90 = LogEntry(start: date(2026, 9, 8, 13, 0), end: date(2026, 9, 8, 14, 30), clientNames: ["김코치"], groupSize: 4, kind: .coachTheCoach, ctcComposition: .group, ctcLicenseNumber: "KPC1")
check(ctc60.recordedMinutes == 120 && !lengthCodes(ctc60).contains("ctcDoubled"), "CTC 1:1 for 1 hour = 120 minutes, allowed")
check(lengthCodes(ctc61).contains("ctcDoubled"), "CTC 1:2 over 1 hour exceeds 120 doubled minutes")
check(lengthCodes(ctc29).contains("ctcDoubled"), "CTC 1:1 under 30 minutes (58 doubled) is an error")
check(!lengthCodes(ctcGroup90).contains("ctcLength"), "group CTC is not doubled: 90 minutes allowed")
check(KACValidator.allowedRangeMinutes(for: ctc60) == 30...60, "CTC 1:1 real time range 30...60")

var typed = paid121
typed.minutesOverride = 120
check(lengthCodes(typed).contains("lengthRange"), "typing 120 does not hide a 121-minute time range")
var typedCTC = ctc61
typedCTC.minutesOverride = 120
check(lengthCodes(typedCTC).contains("ctcDoubledRange"), "typing 120 does not hide a 61-minute CTC")

let fixLong = KACValidator.lengthFix(for: paid121)
check(fixLong?.end == date(2026, 9, 8, 11, 0) && fixLong?.minutesOverride == nil, "too long → end cut to 120 minutes")
let fixCTC = KACValidator.lengthFix(for: ctc61)
check(fixCTC?.end == date(2026, 9, 8, 14, 0), "CTC too long → end cut to 60 real minutes")
check(KACValidator.lengthFix(for: paid29) == nil, "too short is never padded automatically")
check(KACValidator.lengthFix(for: paid120) == nil, "valid entry needs no fix")
var badTyped = paid120
badTyped.minutesOverride = 150
check(KACValidator.lengthFix(for: badTyped) == KACValidator.LengthFix(end: paid120.end, minutesOverride: nil),"typed minutes off → clear override")
if let fixed = fixLong {
    var applied = paid121
    applied.end = fixed.end
    applied.minutesOverride = fixed.minutesOverride
    check(KACValidator.hasValidLength(applied), "applying the fix leaves no length error")
}

print("XLSX")
var entries = [free, ctc, group, e1]
for i in 0..<14 {
    entries.append(LogEntry(start: date(2026, 9, 10 + i, 19, 0), end: date(2026, 9, 10 + i, 19, 45), clientNames: ["고객\(i % 4)"], kind: i % 3 == 0 ? .free : .paid, format: i % 2 == 0 ? .remote : .faceToFace))
}
let builder = KACWorkbookBuilder(candidateName: "이현호", entries: entries, formatter: formatter, createdAt: date(2026, 9, 11, 21, 0))
let data = builder.build()
check(data.count > 20_000, "workbook generated (\(data.count) bytes)")
check(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]), "zip signature")
check(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926, "CRC32 reference value")
let (sheet, lastRow) = builder.sheetXML()
check(lastRow == 7 + entries.count, "total row after \(entries.count) entries")
check(sheet.contains("<f>SUM(D7:D\(lastRow - 1))</f>"), "SUM formula range")
check(sheet.contains("2026-09-01"), "first entry sorted first")

let summary = KACSummary(entries: entries)
check(KACWorkbookBuilder.totalsText(summary).contains("총 코칭시간 합계: \(KACDuration.hoursMinutes(summary.totalMinutes))"), "totals text")

let shortBuilder = KACWorkbookBuilder(candidateName: "이현호", entries: [e1], includeExampleRows: true, formatter: formatter)
check(shortBuilder.sheetXML().lastRow == 19, "short log keeps the template's 12 body rows (total row 19)")

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let outputURL = outputDirectory.appendingPathComponent("sample-코칭일지.xlsx")
try data.write(to: outputURL)
try shortBuilder.build().write(to: outputDirectory.appendingPathComponent("sample-short-with-examples.xlsx"))
print("  → \(outputURL.path)")

print("Training start and total hours")
let beforeTraining = LogEntry(start: date(2026, 8, 31, 23, 0), end: date(2026, 8, 31, 23, 50), clientNames: ["홍길동"])
let onTrainingDay = LogEntry(start: date(2026, 9, 1, 8, 0), end: date(2026, 9, 1, 8, 50), clientNames: ["이몽룡"])
func codes(_ entries: [LogEntry], training: Date? = nil, total: Bool = false) -> [String] {
    KACValidator.validate(entries: entries, candidateName: "이현호", trainingStartDate: training, checkTotalHours: total, formatter: formatter).map(\.code)
}
let trainingCodes = codes([beforeTraining, onTrainingDay], training: date(2026, 9, 1, 14, 0))
check(trainingCodes.filter { $0 == "beforeTraining" }.count == 1, "only the session before the training day is rejected")
check(codes([onTrainingDay]).contains("trainingStart"), "missing training start date is flagged")
check(!codes([onTrainingDay], training: date(2026, 9, 1, 0, 0)).contains("trainingStart"), "no reminder once the date is set")
check(codes([onTrainingDay], total: true).contains("totalRequired"), "under 50 hours is flagged on export")
check(!codes([onTrainingDay]).contains("totalRequired"), "total hours are not checked while logging")
let fiftyTwo = (0..<26).map { day in
    LogEntry(start: date(2026, 10, 1, 9, 0).addingTimeInterval(Double(day) * 86_400), end: date(2026, 10, 1, 11, 0).addingTimeInterval(Double(day) * 86_400), clientNames: ["고객\(day % 4)"])
}
let marginCodes = codes(fiftyTwo, total: true)
check(marginCodes.contains("totalMargin") && !marginCodes.contains("totalRequired"), "52 hours: enough but below the 55-hour margin")

print("Certifications")
func certCodes(_ entries: [LogEntry], _ certification: Certification, total: Bool = false) -> [String] {
    KACValidator.validate(entries: entries, candidateName: "이현호", certification: certification, trainingStartDate: date(2026, 1, 1, 0, 0), checkTotalHours: total, formatter: formatter).map(\.code)
}
check(Certification.kac.requiredTotalMinutes == 50 * 60 && Certification.kac.recommendedTotalMinutes == 55 * 60, "KAC 50 hours, 55-hour margin")
check(Certification.kpc.practiceHours == 200 && Certification.kpc.maxCTCHours == 80, "KPC 200 hours, CTC up to 80")
check(Certification.ksc.practiceHours == 800 && Certification.ksc.maxCTCHours == 100, "KSC 800 hours, CTC up to 100")
check(Certification.acc.minimumPaidHours == 75 && Certification.pcc.minimumPaidHours == 450 && Certification.mcc.minimumPaidHours == 2250, "ICF paid hours")
check(certCodes(fiftyTwo, .kpc, total: true).contains("totalRequired"), "52 hours is short for KPC")
check(!certCodes(fiftyTwo, .kac, total: true).contains("totalRequired"), "52 hours is enough for KAC")

let ctcHours = (0..<14).map { day in
    LogEntry(start: date(2026, 11, 1, 9, 0).addingTimeInterval(Double(day) * 86_400), end: date(2026, 11, 1, 10, 0).addingTimeInterval(Double(day) * 86_400), clientNames: ["김코치"], kind: .coachTheCoach, ctcComposition: .oneOnOne, ctcLicenseNumber: "KSC1")
}
check(certCodes(ctcHours, .kac).contains("ctcTotal"), "28 CTC hours exceed the KAC 25-hour cap")
check(!certCodes(ctcHours, .kpc).contains("ctcTotal"), "28 CTC hours are fine for KPC")

let longICF = LogEntry(start: date(2026, 9, 8, 9, 0), end: date(2026, 9, 8, 12, 0), clientNames: ["홍길동"])
check(!certCodes([longICF], .acc).contains("length"), "ICF has no 120-minute session limit")
check(certCodes([longICF], .kac).contains("length"), "KCA keeps the 120-minute session limit")
check(certCodes([ctc], .acc).contains("icfCTC"), "coach-the-coach is flagged for ICF")
check(KACSummary(entries: [e1, ctc], certification: .acc).totalMinutes == e1.recordedMinutes, "ICF totals leave out coach-the-coach")
check(certCodes([e1, free], .acc).contains("clients"), "ACC needs 8 clients")
let icfPaid = certCodes(fiftyTwo, .acc, total: true)
check(icfPaid.contains("totalRequired") && icfPaid.contains("paidRequired"), "52 paid hours: short of 100 total and 75 paid")
let eightyPaid = (0..<40).map { day in
    LogEntry(start: date(2026, 10, 1, 9, 0).addingTimeInterval(Double(day) * 86_400), end: date(2026, 10, 1, 11, 0).addingTimeInterval(Double(day) * 86_400), clientNames: ["고객\(day % 8)"])
}
check(!certCodes(eightyPaid, .acc, total: true).contains("paidRequired"), "80 paid hours meet the ACC paid share")
check(certCodes([free], .acc, total: true).contains("paidRequired"), "ICF flags missing paid hours")
let big = LogEntry(start: date(2026, 9, 9, 9, 0), end: date(2026, 9, 9, 10, 0), clientNames: ["가"], groupSize: 12)
check(!certCodes([big], .acc).contains("groupSize") && certCodes([big], .kac).contains("groupSize"), "group of 12: ICF ok, KCA over 1:9")

print("ICF log")
check(ICFLogBuilder.hours(50) == "0.83" && ICFLogBuilder.hours(90) == "1.5" && ICFLogBuilder.hours(120) == "2", "decimal hours")
check(ICFLogBuilder.escape("가, 나") == "\"가, 나\"", "CSV escaping")
let icf = ICFLogBuilder(candidateName: "이현호", entries: [free, ctc, group, e1], formatter: formatter)
check(icf.rows.count == 3 && icf.rows.first?[4] == "2026-09-01", "sorted rows without coach-the-coach")
check(icf.rows.contains { $0[2] == "Group" && $0[3] == "6" }, "group row with size")
let csvText = icf.csv()
check(csvText.contains("Total,,,,,,2.83,1"), "totals row: paid 2:50 → 2.83, pro bono 1")
check(icf.build().prefix(3) == Data([0xEF, 0xBB, 0xBF]), "UTF-8 BOM for Excel")
try icf.build().write(to: outputDirectory.appendingPathComponent("sample-icf-log.csv"))

print(failures == 0 ? "\nALL CORE CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
