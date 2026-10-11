import Testing
@testable import ReminderCore

struct CSVParserTests {
    @Test func parsesQuotedFieldsWithCommasQuotesAndNewlines() {
        let text = "\"a\",\"b, c\",\"d \"\"e\"\"\"\n\"multi\nline\",x,\"\"\n"
        let rows = CSVParser.parse(text)
        #expect(rows.map(\.fields) == [["a", "b, c", "d \"e\""], ["multi\nline", "x", ""]])
        #expect(rows.map(\.line) == [1, 2])
    }

    @Test func handlesCRLFBOMAndBlankLines() {
        let text = "\u{FEFF}h1,h2\r\n\r\n1,2\r\n3,4"
        let rows = CSVParser.parse(text)
        #expect(rows.map(\.fields) == [["h1", "h2"], ["1", "2"], ["3", "4"]])
        #expect(rows.map(\.line) == [1, 3, 4])
    }

    @Test func keepsEmojiAndAccents() {
        let rows = CSVParser.parse("\"⚠️✝️ Flyer\",\"Día\"")
        #expect(rows.first?.fields == ["⚠️✝️ Flyer", "Día"])
    }

    @Test func detectsSemicolonDelimiter() {
        let rows = CSVParser.parse("\"t;x\";fecha;repetir\nuno;2026-01-01;\n")
        #expect(rows.map(\.fields) == [["t;x", "fecha", "repetir"], ["uno", "2026-01-01", ""]])
    }

    @Test func trailingEmptyQuotedFieldCountsAsRow() {
        let rows = CSVParser.parse("a,\"\"")
        #expect(rows.map(\.fields) == [["a", ""]])
    }
}
