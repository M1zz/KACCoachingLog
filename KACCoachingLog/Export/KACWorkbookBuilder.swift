import Foundation

/// Builds an .xlsx that reproduces the official KAC 코칭일지 template (인증_1_34_v6) and fills in the sessions.
///
/// Layout (identical to the template):
///  1  template version        2  《코칭일지》          3  notice (rules 1–9)
///  4  응시자 명(필수작성):     5  sort instruction      6  column headers
///  7… entries (at least 12 rows, like the template)
///  last row: 합계 with SUM formulas and hours/minutes totals
struct KACWorkbookBuilder {
    var candidateName: String
    var entries: [LogEntry]
    var includeExampleRows: Bool = false
    var formatter: KACFormatter = KACFormatter()
    var createdAt: Date = Date()

    /// The official template ships with 12 writable rows (7–18).
    static let minimumBodyRows = 12
    static let firstEntryRow = 7

    // Style indices from the template's styles.xml
    private enum Style {
        static let version = 5, versionTail = 6, versionTail2 = 7
        static let title = 29, titleTail = 30
        static let notice = 31, noticeTail = 33
        static let candidate = 31, candidateTail = 32
        static let instruction = 28
        static let headerDateTime = 16, header = 17
        static let cellCenter = 11, cellCenterWrap = 13
        static let emptyMinutes = 9, emptyRight = 10
        static let totalLabel = 27, totalPaid = 14, totalOther = 15, totalText = 25
    }

    // Shared string indices from the template's sharedStrings.xml
    private enum SST {
        static let version = 27, title = 4, notice = 29, instruction = 28
        static let date = 0, time = 1, client = 5, paid = 7, free = 8, ctc = 3, format = 6
        static let total = 12
    }

    func build() -> Data {
        var zip = ZipWriter(modificationDate: createdAt, timeZone: formatter.timeZone)
        let (sheet, lastRow) = sheetXML()
        zip.addFile(path: "[Content_Types].xml", string: Self.contentTypes)
        zip.addFile(path: "_rels/.rels", string: Self.rootRels)
        zip.addFile(path: "docProps/app.xml", string: Self.appXML)
        zip.addFile(path: "docProps/core.xml", string: coreXML())
        zip.addFile(path: "xl/workbook.xml", string: workbookXML(lastRow: lastRow))
        zip.addFile(path: "xl/_rels/workbook.xml.rels", string: Self.workbookRels)
        zip.addFile(path: "xl/styles.xml", data: KACTemplateParts.stylesXML)
        zip.addFile(path: "xl/theme/theme1.xml", data: KACTemplateParts.themeXML)
        zip.addFile(path: "xl/sharedStrings.xml", data: KACTemplateParts.sharedStringsXML)
        zip.addFile(path: "xl/worksheets/sheet1.xml", string: sheet)
        return zip.finalize()
    }

    // MARK: - Sheet

    func sheetXML() -> (xml: String, lastRow: Int) {
        let ordered = KACValidator.sorted(entries)
        var rows: [String] = []

        // Row 1–6: header block copied from the template
        rows.append(row(1, height: 18, cells: [
            sharedCell("A1", Style.version, SST.version),
            emptyCell("B1", Style.version), emptyCell("C1", Style.version),
            emptyCell("D1", Style.versionTail),
            emptyCell("E1", Style.versionTail2), emptyCell("F1", Style.versionTail2), emptyCell("G1", Style.versionTail2),
        ]))
        rows.append(row(2, height: 28.5, cells:
            [sharedCell("A2", Style.title, SST.title)] + tail(row: 2, style: Style.titleTail)))
        rows.append(row(3, height: 370.5, cells:
            [sharedCell("A3", Style.notice, SST.notice)] + tail(row: 3, style: Style.noticeTail)))
        rows.append(row(4, height: 30, cells: [
            candidateCell("A4"),
            emptyCell("B4", Style.candidate),
        ] + ["C", "D", "E", "F", "G"].map { emptyCell("\($0)4", Style.candidateTail) }))
        rows.append(row(5, height: 22.5, cells:
            [sharedCell("A5", Style.instruction, SST.instruction)] + tail(row: 5, style: Style.instruction)))
        rows.append(row(6, height: 36, cells: [
            sharedCell("A6", Style.headerDateTime, SST.date),
            sharedCell("B6", Style.headerDateTime, SST.time),
            sharedCell("C6", Style.header, SST.client),
            sharedCell("D6", Style.header, SST.paid),
            sharedCell("E6", Style.header, SST.free),
            sharedCell("F6", Style.header, SST.ctc),
            sharedCell("G6", Style.header, SST.format),
        ]))

        var rowNumber = Self.firstEntryRow
        if includeExampleRows {
            rows.append(contentsOf: Self.exampleRows)
            rowNumber += Self.exampleRows.count
        }
        let firstDataRow = rowNumber

        for entry in ordered {
            let r = rowNumber
            let height = formatter.isMultiline(entry) ? 62.25 : 32.25
            rows.append(row(r, height: height, cells: [
                textCell("A\(r)", Style.cellCenter, formatter.dateText(entry)),
                textCell("B\(r)", Style.cellCenter, formatter.timeText(entry)),
                textCell("C\(r)", Style.cellCenterWrap, formatter.clientText(entry)),
                minutesCell("D\(r)", entry.paidMinutes, isActive: entry.kind == .paid),
                minutesCell("E\(r)", entry.freeMinutes, isActive: entry.kind == .free),
                minutesCell("F\(r)", entry.ctcMinutes, isActive: entry.kind == .coachTheCoach),
                textCell("G\(r)", Style.cellCenterWrap, formatter.formatText(entry)),
            ]))
            rowNumber += 1
        }

        // Pad with the template's empty rows so short logs still look like the original form
        let usedBodyRows = rowNumber - Self.firstEntryRow
        if usedBodyRows < Self.minimumBodyRows {
            for _ in usedBodyRows..<Self.minimumBodyRows {
                let r = rowNumber
                rows.append(row(r, height: 32.25, cells: [
                    emptyCell("A\(r)", Style.cellCenter), emptyCell("B\(r)", Style.cellCenter), emptyCell("C\(r)", Style.cellCenter),
                    emptyCell("D\(r)", Style.emptyMinutes),
                    emptyCell("E\(r)", Style.emptyRight), emptyCell("F\(r)", Style.emptyRight), emptyCell("G\(r)", Style.emptyRight),
                ]))
                rowNumber += 1
            }
        }

        let lastBodyRow = rowNumber - 1
        let totalRow = rowNumber
        let summary = KACSummary(entries: ordered)
        // Example rows contain text only, so SUM over them adds nothing; start from row 7 like the template.
        let sumStart = includeExampleRows ? Self.firstEntryRow : firstDataRow
        rows.append(row(totalRow, height: 112.5, cells: [
            sharedCell("A\(totalRow)", Style.totalLabel, SST.total),
            emptyCell("B\(totalRow)", Style.totalLabel), emptyCell("C\(totalRow)", Style.totalLabel),
            formulaCell("D\(totalRow)", Style.totalPaid, "SUM(D\(sumStart):D\(lastBodyRow))", summary.paidMinutes),
            formulaCell("E\(totalRow)", Style.totalOther, "SUM(E\(sumStart):E\(lastBodyRow))", summary.freeCoachingMinutes),
            formulaCell("F\(totalRow)", Style.totalOther, "SUM(F\(sumStart):F\(lastBodyRow))", summary.ctcMinutes),
            textCell("G\(totalRow)", Style.totalText, Self.totalsText(summary)),
        ]))

        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>\
        <dimension ref="A1:G\(totalRow)"/>\
        <sheetViews><sheetView tabSelected="1" zoomScaleNormal="100" workbookViewId="0"><selection activeCell="A7" sqref="A7"/></sheetView></sheetViews>\
        <sheetFormatPr defaultColWidth="8.8984375" defaultRowHeight="17.399999999999999"/>\
        <cols>\
        <col min="1" max="1" width="18.69921875" style="2" customWidth="1"/>\
        <col min="2" max="2" width="14" style="2" customWidth="1"/>\
        <col min="3" max="3" width="28.09765625" style="2" customWidth="1"/>\
        <col min="4" max="4" width="11.3984375" style="3" customWidth="1"/>\
        <col min="5" max="5" width="11.3984375" style="4" customWidth="1"/>\
        <col min="6" max="6" width="14.59765625" style="4" customWidth="1"/>\
        <col min="7" max="7" width="24.3984375" style="4" customWidth="1"/>\
        <col min="8" max="16384" width="8.8984375" style="1"/>\
        </cols>\
        <sheetData>\(rows.joined())</sheetData>\
        <mergeCells count="5"><mergeCell ref="A2:G2"/><mergeCell ref="A3:G3"/><mergeCell ref="A4:G4"/><mergeCell ref="A5:G5"/><mergeCell ref="A\(totalRow):C\(totalRow)"/></mergeCells>\
        <pageMargins left="0.23622047244094491" right="0.23622047244094491" top="0" bottom="0" header="0.31496062992125984" footer="0.31496062992125984"/>\
        <pageSetup paperSize="9" scale="67" fitToHeight="0" orientation="portrait"/>\
        </worksheet>
        """
        return (xml, totalRow)
    }

    static func totalsText(_ summary: KACSummary) -> String {
        """
        총 유료 코칭 시간: \(KACDuration.formHoursMinutes(summary.paidMinutes))
        총 무료 코칭 시간: \(KACDuration.formHoursMinutes(summary.totalFreeMinutes))

        총 코칭시간 합계: \(KACDuration.formHoursMinutes(summary.totalMinutes))
        """
    }

    // MARK: - Cell helpers

    private func row(_ number: Int, height: Double, cells: [String]) -> String {
        "<row r=\"\(number)\" spans=\"1:7\" ht=\"\(height)\" customHeight=\"1\">\(cells.joined())</row>"
    }

    private func tail(row: Int, style: Int) -> [String] {
        ["B", "C", "D", "E", "F", "G"].map { emptyCell("\($0)\(row)", style) }
    }

    private func emptyCell(_ ref: String, _ style: Int) -> String {
        "<c r=\"\(ref)\" s=\"\(style)\"/>"
    }

    private func sharedCell(_ ref: String, _ style: Int, _ index: Int) -> String {
        "<c r=\"\(ref)\" s=\"\(style)\" t=\"s\"><v>\(index)</v></c>"
    }

    private func textCell(_ ref: String, _ style: Int, _ text: String) -> String {
        if text.isEmpty { return emptyCell(ref, style) }
        return "<c r=\"\(ref)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(XML.escape(text))</t></is></c>"
    }

    private func minutesCell(_ ref: String, _ minutes: Int, isActive: Bool) -> String {
        guard isActive else { return emptyCell(ref, Style.cellCenter) }
        return "<c r=\"\(ref)\" s=\"\(Style.cellCenter)\"><v>\(minutes)</v></c>"
    }

    private func formulaCell(_ ref: String, _ style: Int, _ formula: String, _ cached: Int) -> String {
        "<c r=\"\(ref)\" s=\"\(style)\"><f>\(formula)</f><v>\(cached)</v></c>"
    }

    /// "응시자 명(필수작성): 이름" — keeps the template's red "(필수작성)" run.
    private func candidateCell(_ ref: String) -> String {
        let runFont = "<rFont val=\"나눔고딕\"/><family val=\"3\"/><charset val=\"129\"/>"
        let name = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "<c r=\"\(ref)\" s=\"\(Style.candidate)\" t=\"inlineStr\"><is>"
            + "<r><rPr><b/><sz val=\"10\"/>\(runFont)</rPr><t>응시자 명</t></r>"
            + "<r><rPr><b/><sz val=\"10\"/><color rgb=\"FFFF0000\"/>\(runFont)</rPr><t>(필수작성)</t></r>"
            + "<r><rPr><b/><sz val=\"10\"/>\(runFont)</rPr><t xml:space=\"preserve\">: \(XML.escape(name))</t></r>"
            + "</is></c>"
    }

    // MARK: - Example rows (rows 7–10 of the template)

    private static let exampleRows: [String] = [
        "<row r=\"7\" spans=\"1:7\" ht=\"37.5\" customHeight=\"1\"><c r=\"A7\" s=\"19\" t=\"s\"><v>17</v></c><c r=\"B7\" s=\"8\" t=\"s\"><v>13</v></c><c r=\"C7\" s=\"11\" t=\"s\"><v>2</v></c><c r=\"D7\" s=\"11\" t=\"s\"><v>9</v></c><c r=\"E7\" s=\"13\"/><c r=\"F7\" s=\"13\"/><c r=\"G7\" s=\"24\" t=\"s\"><v>21</v></c></row>",
        "<row r=\"8\" spans=\"1:7\" ht=\"32.25\" customHeight=\"1\"><c r=\"A8\" s=\"19\" t=\"s\"><v>18</v></c><c r=\"B8\" s=\"8\" t=\"s\"><v>14</v></c><c r=\"C8\" s=\"11\" t=\"s\"><v>2</v></c><c r=\"D8\" s=\"11\"/><c r=\"E8\" s=\"13\" t=\"s\"><v>10</v></c><c r=\"F8\" s=\"13\"/><c r=\"G8\" s=\"24\" t=\"s\"><v>21</v></c></row>",
        "<row r=\"9\" spans=\"1:7\" ht=\"62.25\" customHeight=\"1\"><c r=\"A9\" s=\"12\" t=\"s\"><v>19</v></c><c r=\"B9\" s=\"8\" t=\"s\"><v>15</v></c><c r=\"C9\" s=\"13\" t=\"s\"><v>24</v></c><c r=\"D9\" s=\"11\"/><c r=\"E9\" s=\"13\"/><c r=\"F9\" s=\"26\" t=\"s\"><v>11</v></c><c r=\"G9\" s=\"24\" t=\"s\"><v>21</v></c></row>",
        "<row r=\"10\" spans=\"1:7\" ht=\"62.25\" customHeight=\"1\"><c r=\"A10\" s=\"20\" t=\"s\"><v>20</v></c><c r=\"B10\" s=\"21\" t=\"s\"><v>16</v></c><c r=\"C10\" s=\"22\" t=\"s\"><v>22</v></c><c r=\"D10\" s=\"23\" t=\"s\"><v>11</v></c><c r=\"E10\" s=\"18\"/><c r=\"F10\" s=\"18\"/><c r=\"G10\" s=\"24\" t=\"s\"><v>26</v></c></row>",
    ]

    // MARK: - Package parts

    private func workbookXML(lastRow: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <workbookPr defaultThemeVersion="124226"/>\
        <bookViews><workbookView xWindow="0" yWindow="0" windowWidth="23040" windowHeight="7932"/></bookViews>\
        <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>\
        <definedNames><definedName name="_xlnm.Print_Area" localSheetId="0">Sheet1!$A$2:$G$\(lastRow)</definedName></definedNames>\
        <calcPr calcId="191029" fullCalcOnLoad="1"/>\
        </workbook>
        """
    }

    private func coreXML() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let stamp = iso.string(from: createdAt)
        let name = XML.escape(candidateName.trimmingCharacters(in: .whitespacesAndNewlines))
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <dc:title>코칭일지</dc:title><dc:creator>\(name)</dc:creator><cp:lastModifiedBy>\(name)</cp:lastModifiedBy>\
        <dcterms:created xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:created>\
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:modified>\
        </cp:coreProperties>
        """
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    <Override PartName="/xl/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>\
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
    <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
    <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>\
    </Types>
    """

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    private static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>\
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
    <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>\
    </Relationships>
    """

    private static let appXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">\
    <Application>Microsoft Excel</Application><DocSecurity>0</DocSecurity><ScaleCrop>false</ScaleCrop>\
    <LinksUpToDate>false</LinksUpToDate><SharedDoc>false</SharedDoc><HyperlinksChanged>false</HyperlinksChanged><AppVersion>16.0300</AppVersion>\
    </Properties>
    """
}

enum XML {
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "\r": continue
            case "\n", "\t": result.unicodeScalars.append(scalar)
            default:
                // XML 1.0 forbids most control characters
                if scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
