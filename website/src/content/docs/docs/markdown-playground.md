---
title: Markdown Playground
description: Sample content for reviewing documentation typography, spacing, and Markdown elements.
sidebar:
  order: 999
  attrs:
    data-viku-icon: overview
---

This page contains **dummy content for visual review**. Use it to compare the documentation in light and dark mode, on narrow screens, and while scrolling beneath the translucent header. The examples below are illustrative, not setup instructions.

## Text and links

A regular paragraph with **bold text**, *italic text*, ***bold italic text***, ~~strikethrough text~~, and `inline code`. Here is an [internal link to the documentation overview](/docs/), an [external link to Vikunja](https://vikunja.io), and a [link to the callouts on this page](#callouts).

A second paragraph helps check the spacing between blocks. Documentation should remain comfortable to read when a sentence wraps onto several lines, especially on a small screen or with a larger browser font size.

Special characters and escaped Markdown: &amp;, &lt;example&gt;, \*literal asterisks\*, and \`literal backticks\`.

## Small text

This is a regular paragraph for comparing text sizes.

<small>This is small text, suitable for a secondary note or clarification beneath the main content.</small>

## Heading hierarchy

The page title provides the only level-one heading. Article sections start at level two.

### Level-three heading

A short paragraph beneath a subsection heading.

#### Level-four heading

A smaller subsection with some supporting text.

##### Level-five heading

A deeper heading for checking the type scale.

###### Level-six heading

The deepest heading supported by Markdown.

## Unordered lists

- A short list item.
- An item with **emphasis** and `inline code`.
- A longer item that wraps onto several lines on smaller screens, so we can review indentation and line height alongside the rest of the article.
- An item with nested options:
  - A second-level item.
  - Another second-level item.
    - A third-level item.

## Ordered lists

1. Open the sample project.
2. Review the available views.
   1. Check the list view.
   2. Check the board view.
3. Compare the results.

   This second paragraph belongs to the third step. It checks the spacing and indentation of multi-paragraph list items.

4. Finish the review.

### Numbering from a different starting point

7. Resume the review at step seven.
8. Confirm that the next number follows automatically.

## Task lists

- [x] Review the sidebar.
- [x] Review the topbar.
- [ ] Review the article typography.
- [ ] Check small screens and both color themes.

These checkboxes are examples of Markdown task lists, not interactive task controls.

## Code

Inline code can appear in a sentence, such as `task.title`, or inside **emphasized text with `code`**.

### Shell command

```sh
printf '%s\n' 'This is a sample command.'
```

### Syntax highlighting and filename

```ts title="sample-task.ts"
interface Task {
  title: string;
  done: boolean;
}

const task: Task = {
  title: 'Review the documentation styles',
  done: false,
};

console.log(task.title);
```

### Highlighted lines

```json {3} title="sample-task.json"
{
  "title": "Review the documentation styles",
  "done": true,
  "labels": ["design", "documentation"]
}
```

### Plain text and long lines

```text
No syntax highlighting is needed for this block.
This deliberately long line checks horizontal scrolling inside a code block without widening the article or pushing the sidebar out of place on smaller screens.
```

## Callouts

:::note{icon="document"}
This is a note with **bold text**, `inline code`, and a [documentation link](/docs/).
:::

:::tip[Helpful tip]{icon="star"}
Use the theme selector to compare this page in light and dark mode.
:::

:::caution[Example warning]{icon="warning"}
This is placeholder content. Do not treat the sample commands as configuration instructions.
:::

:::danger[Example danger message]{icon="error"}
A stronger callout can include a short list:

- Explain the consequence clearly.
- Provide a recovery path.
:::

## Blockquotes

> A blockquote can highlight a passage without using a callout.
>
> It can contain multiple paragraphs, **emphasis**, and [links](/docs/).

> An outer quotation.
>
> > A nested quotation for checking indentation.

## Tables

| Element | Purpose | Example |
| --- | --- | --- |
| **Title** | Identify the page | Markdown Playground |
| `inline code` | Show a technical identifier | `task.done` |
| Link | Navigate to another page | [Overview](/docs/) |
| Longer text | Check wrapping inside a table cell | This sentence is deliberately long enough to wrap on a small screen. |

| Left aligned | Center aligned | Right aligned |
| :--- | :---: | ---: |
| Tasks | Ready | 12 |
| Projects | Pending | 3 |

## Horizontal rule

A paragraph before a thematic break.

---

A paragraph after the break.

## Images

![Viku app icon, a blue square with a white checkmark and orange accent](../../../assets/logo.png)

An image with descriptive alternative text, using a local asset rather than an external placeholder service.

## Expandable details

<details>
<summary>Show a sample explanation</summary>

This content is collapsed by default. It includes **Markdown formatting** and a list:

- First detail.
- Second detail.

```text
Sample output inside an expandable section.
```

</details>

<details open>
<summary>An explanation that starts expanded</summary>

Use this second example to compare open and closed disclosure controls.

</details>

## Inline HTML

Keyboard shortcut: <kbd>⌘</kbd> + <kbd>K</kbd>. A sample abbreviation: <abbr title="Application Programming Interface">API</abbr>. Superscript: x<sup>2</sup>. Subscript: H<sub>2</sub>O. Highlighted text: <mark>Review this example</mark>.

## Footnotes

This sentence has a footnote.[^sample] Another sentence references a longer note.[^longer]

[^sample]: A short sample footnote.
[^longer]: A longer footnote with **formatted text** and a [link back to the overview](/docs/).
