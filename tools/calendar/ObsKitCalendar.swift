// ObsKit Calendar — reads today's meetings from macOS Calendar (EventKit) and writes a
// small, camera-safe summary for the meeting overlays and the OBS startup script.
//
//   ObsKit Calendar.app --out <dir> [--calendars "Work,Team"]
//
// Writes <dir>/calendar.json and <dir>/calendar.js (window.OBSKIT_CALENDAR = …), then exits.
// Only titles, times, attendee counts, the call platform and agenda bullet lines are written —
// never links, passcodes, dial-ins, notes or attendee emails.
import EventKit
import Foundation

let args = CommandLine.arguments
func arg(_ name: String) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  return args[i + 1]
}
let outDir = URL(fileURLWithPath: arg("--out") ?? FileManager.default.currentDirectoryPath, isDirectory: true)
let onlyCalendars = (arg("--calendars") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }

func write(_ payload: [String: Any]) {
  try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
  guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
        let json = String(data: data, encoding: .utf8) else { return }
  // Write via temp files + rename so readers never see half a file
  for (name, body) in [("calendar.json", json), ("calendar.js", "window.OBSKIT_CALENDAR = \(json);\n")] {
    let tmp = outDir.appendingPathComponent(".\(name).tmp"), dst = outDir.appendingPathComponent(name)
    try? body.write(to: tmp, atomically: false, encoding: .utf8)
    _ = try? FileManager.default.replaceItemAt(dst, withItemAt: tmp) ?? { try FileManager.default.moveItem(at: tmp, to: dst); return dst }()
  }
}
let nowMs = { Int64(Date().timeIntervalSince1970 * 1000) }

// ── Agenda: bullet/numbered lines from the invite, with risky lines removed ──
let unsafe = try! NSRegularExpression(pattern: #"(pass ?code|password|pwd|\bpin\b|meeting id|webinar id|dial|join|https?://|www\.|@|\+?\d[\d\s().-]{7,}|zoom\.us|meet\.google|teams\.microsoft)"#, options: [.caseInsensitive])
let bullet = try! NSRegularExpression(pattern: #"^\s*(?:[-*•▪◦–]|\d{1,2}[.)]|[a-z][.)])\s+(.+)$"#, options: [.caseInsensitive])
let minutesRx = try! NSRegularExpression(pattern: #"[\[(–—-]?\s*(\d{1,3})\s*(?:m|min|mins|minutes)\b\s*[\])]?"#, options: [.caseInsensitive])

func plain(_ s: String) -> String {
  var t = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
  t = t.replacingOccurrences(of: "</(p|li|div)>", with: "\n", options: [.regularExpression, .caseInsensitive])
  t = t.replacingOccurrences(of: "<li[^>]*>", with: "\n- ", options: [.regularExpression, .caseInsensitive])
  t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
  for (a, b) in [("&amp;", "&"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&#39;", "'"), ("&quot;", "\"")] { t = t.replacingOccurrences(of: a, with: b) }
  return t
}

func agenda(from notes: String?) -> [[String: Any]] {
  guard let raw = notes, !raw.isEmpty else { return [] }
  var lines = plain(raw).components(separatedBy: .newlines)
  // Prefer an explicit "Agenda" section when there is one
  if let i = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).range(of: #"^agenda\s*:?\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil }) {
    lines = Array(lines[(i + 1)...])
  }
  var items: [[String: Any]] = []
  for line in lines {
    let ns = line as NSString
    guard let m = bullet.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
      if !items.isEmpty && line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
      continue
    }
    var text = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
    if unsafe.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil { continue }
    var minutes: Int? = nil
    if let mm = minutesRx.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
      minutes = Int((text as NSString).substring(with: mm.range(at: 1)))
      text = (text as NSString).replacingCharacters(in: mm.range, with: "").trimmingCharacters(in: CharacterSet(charactersIn: " -–—:,"))
    }
    if text.isEmpty { continue }
    if text.count > 80 { text = String(text.prefix(79)) + "…" }
    var item: [String: Any] = ["text": text]
    if let mi = minutes, mi > 0 { item["minutes"] = mi }
    items.append(item)
    if items.count >= 10 { break }
  }
  return items
}

func platform(_ e: EKEvent) -> String? {
  let hay = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ").lowercased()
  if hay.contains("zoom.us") { return "zoom" }
  if hay.contains("meet.google.com") { return "meet" }
  if hay.contains("teams.microsoft.com") || hay.contains("teams.live.com") { return "teams" }
  if hay.contains("webex.com") { return "webex" }
  return nil
}

// ── Main ──
let store = EKEventStore()
let sem = DispatchSemaphore(value: 0)
var granted = false
store.requestFullAccessToEvents { ok, _ in granted = ok; sem.signal() }
_ = sem.wait(timeout: .now() + 120)

guard granted else {
  write(["status": "denied", "generated": nowMs(), "events": [],
         "help": "Allow ObsKit Calendar in System Settings → Privacy & Security → Calendars."])
  exit(0)
}

var cals = store.calendars(for: .event).filter { $0.type != .birthday && !$0.title.lowercased().contains("holiday") }
if !onlyCalendars.isEmpty { cals = cals.filter { onlyCalendars.contains($0.title.lowercased()) || onlyCalendars.contains($0.source.title.lowercased()) } }

let now = Date()
let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600), end: now.addingTimeInterval(24 * 3600), calendars: cals)
let events = store.events(matching: pred)
  .filter { !$0.isAllDay && $0.endDate > now }
  .filter { e in !(e.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined } }
  .filter { e in (e.attendees?.count ?? 0) > 1 || platform(e) != nil }        // meetings, not solo blocks
  .sorted { $0.startDate < $1.startDate }
  .prefix(20)

let out: [[String: Any]] = events.map { e in
  var d: [String: Any] = [
    "id": "\(e.calendarItemIdentifier)@\(Int64(e.startDate.timeIntervalSince1970))",
    "title": e.title ?? "Meeting",
    "start": Int64(e.startDate.timeIntervalSince1970 * 1000),
    "end": Int64(e.endDate.timeIntervalSince1970 * 1000),
    "attendees": e.attendees?.count ?? 0,
    "agenda": agenda(from: e.notes),
  ]
  if let p = platform(e) { d["platform"] = p }
  return d
}
write(["status": "ok", "generated": nowMs(), "calendars": cals.count, "events": out])
exit(0)
