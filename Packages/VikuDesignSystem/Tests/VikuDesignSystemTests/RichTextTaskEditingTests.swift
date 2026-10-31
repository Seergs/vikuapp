import Foundation
import Testing
@testable import VikuDesignSystem

@Suite("Rich-text checkbox editing")
struct RichTextTaskEditingTests {
    @Test
    func `checking and unchecking preserves unrelated HTML verbatim`() throws {
        let before = #"<!--keep--><h2>Résumé &amp; 🐈</h2><ul data-type="taskList">"#
            + #"<li data-type="taskItem" data-checked='false' class="keep">"#
            + #"<label><input type="checkbox"><span></span></label><div><p><strong>Same</strong></p>"#
            + #"<img src="x"><table><tr><td>keep</td></tr></table></div></li></ul>"#
        let checked = try toggle(firstItem(in: before), in: before)
        let expected = before.replacingOccurrences(of: "data-checked='false'", with: "data-checked=\"true\"")
            .replacingOccurrences(of: #"type="checkbox">"#, with: #"type="checkbox" checked>"#)
        #expect(checked == expected)
        #expect(try firstItem(in: checked).isChecked)
        let unchecked = try toggle(firstItem(in: checked), in: checked)
        #expect(unchecked == expected.replacingOccurrences(of: #"data-checked="true""#, with: #"data-checked="false""#)
            .replacingOccurrences(of: " checked>", with: " >"))
        #expect(try !firstItem(in: unchecked).isChecked)
    }

    @Test
    func `duplicate text identifies the second item independently`() throws {
        let item = #"<li data-type="taskItem" data-checked="false"><p>Same</p></li>"#
        let html = #"<ul data-type="taskList">\#(item)\#(item)</ul>"#
        guard case let .taskList(items) = RichText.parse(html).first else {
            Issue.record("Expected task list")
            return
        }
        let updated = try toggle(items[1], in: html)
        let checkedItem = item.replacingOccurrences(of: "false", with: "true")
        #expect(updated == #"<ul data-type="taskList">\#(item)\#(checkedItem)</ul>"#)
    }

    @Test
    func `parent toggle does not change nested checkbox state`() throws {
        let child = #"<ul data-type="taskList"><li data-type="taskItem" data-checked="false">"#
            + #"<label><input type="checkbox"></label><div><p>Child</p></div></li></ul>"#
        let html = #"<ul data-type="taskList"><li data-type="taskItem" data-checked="false">"#
            + #"<label><input type="checkbox"></label><div><p>Parent</p>\#(child)</div></li></ul>"#
        let parent = try firstItem(in: html)
        let updated = try toggle(parent, in: html)
        #expect(updated.contains(child))
        #expect(try firstItem(in: updated).isChecked)

        guard case let .taskList(children) = parent.content.last else {
            Issue.record("Expected nested list")
            return
        }
        let childUpdated = try toggle(children[0], in: html)
        #expect(try !firstItem(in: childUpdated).isChecked)
        #expect(childUpdated.contains(child.replacingOccurrences(of: "false", with: "true")
                .replacingOccurrences(of: #"type="checkbox">"#, with: #"type="checkbox" checked>"#)))
    }

    @Test(arguments: ["checked", "CHECKED='checked'", "checked=\"false\""])
    func `unchecking removes boolean checked attributes`(attribute: String) throws {
        let prefix = #"<ul data-type='taskList'><li data-checked=true><label>"#
        let suffix = "</label><p>Item</p></li></ul>"
        let html = prefix + #"<input type='checkbox' \#(attribute) />"# + suffix
        let updated = try toggle(firstItem(in: html), in: html)
        let expected = prefix.replacingOccurrences(of: "data-checked=true", with: #"data-checked="false""#)
            + "<input type='checkbox'  />" + suffix
        #expect(updated == expected)
    }

    @Test
    func `quoted attribute contents are never edited`() throws {
        let prefix = #"<ul data-type="taskList"><li title='data-checked="false" > checked' "#
        let suffix = "</label><p>x</p></li></ul>"
        let html = prefix + #"data-checked="false"><label><input title='checked >' type="checkbox" />"# + suffix
        let updated = try toggle(firstItem(in: html), in: html)
        let expected = prefix
            + #"data-checked="true"><label><input title='checked >' type="checkbox" checked/>"# + suffix
        #expect(updated == expected)
    }

    @Test
    func `missing state attribute is inserted without requiring input markup`() throws {
        let html = #"<blockquote><ul data-type="taskList"><li><p>Item</p></li></ul></blockquote>"#
        guard case let .blockquote(blocks) = RichText.parse(html).first,
              case let .taskList(items) = blocks.first else {
            Issue.record("Expected quoted task list")
            return
        }
        let updated = try toggle(items[0], in: html)
        #expect(updated == html.replacingOccurrences(of: "<li>", with: #"<li data-checked="true">"#))
    }

    @Test(arguments: [-1, 0, 100])
    func `invalid references do not produce an edit`(index: Int) {
        #expect(RichText.togglingTaskItem(at: index, in: "<p>Text</p>") == nil)
    }

    private func toggle(_ item: RichTextTaskItem, in html: String) throws -> String {
        let index = try #require(item.sourceTokenIndex)
        return try #require(RichText.togglingTaskItem(at: index, in: html))
    }

    private func firstItem(in html: String) throws -> RichTextTaskItem {
        let items = RichText.parse(html).compactMap { block -> [RichTextTaskItem]? in
            guard case let .taskList(items) = block else { return nil }
            return items
        }.flatMap(\.self)
        return try #require(items.first)
    }
}
