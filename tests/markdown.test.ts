import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

/** The browser module runs in a bare context: no DOM and no network, only the URL parser browsers have. */
function load() {
  const context = vm.createContext({ URL });
  vm.runInContext(readFileSync("public/markdown.js", "utf8"), context);
  return context.StrudelMarkdown;
}
const md = load();

/** A tiny DOM that records what the renderer builds and refuses HTML parsing. */
class FakeNode {
  children: FakeNode[] = [];
  attributes: Record<string, string> = {};
  data = "";
  dataset: Record<string, string> = {};
  style: Record<string, unknown> = { setProperty(this: Record<string, string>, name: string, value: string) { this[name] = value; } };
  className = "";
  onclick: unknown = null;
  constructor(public tagName: string, public nodeType = 1) {}
  append(...nodes: (FakeNode | string)[]) { for (const node of nodes) this.children.push(typeof node === "string" ? text(node) : node); }
  appendChild(node: FakeNode) { this.children.push(node); return node; }
  setAttribute(name: string, value: string) { this.attributes[name] = String(value); }
  getAttribute(name: string) { return this.attributes[name] ?? null; }
  set href(value: string) { this.attributes.href = value; }
  get href() { return this.attributes.href; }
  set rel(value: string) { this.attributes.rel = value; }
  set target(value: string) { this.attributes.target = value; }
  set dir(value: string) { this.attributes.dir = value; }
  get dir() { return this.attributes.dir; }
  set title(value: string) { this.attributes.title = value; }
  set type(value: string) { this.attributes.type = value; }
  set start(value: number) { this.attributes.start = String(value); }
  set textContent(value: string) { this.children = [text(value)]; }
  get textContent(): string { return this.nodeType === 3 ? this.data : this.children.map((child) => child.textContent).join(""); }
  set innerHTML(_: string) { throw new Error("innerHTML is not allowed"); }
  insertAdjacentHTML() { throw new Error("insertAdjacentHTML is not allowed"); }
  addEventListener() {}
}
function text(value: string) { const node = new FakeNode("#text", 3); node.data = String(value); return node; }
const fakeDocument = {
  createElement: (tag: string) => new FakeNode(tag.toUpperCase()),
  createElementNS: (_: string, tag: string) => new FakeNode(tag),
  createTextNode: text,
  createDocumentFragment: () => new FakeNode("#fragment", 11),
};
function all(node: FakeNode, tag?: string): FakeNode[] {
  const found: FakeNode[] = [];
  const walk = (current: FakeNode) => { if (!tag || current.tagName === tag) found.push(current); current.children.forEach(walk); };
  walk(node);
  return found;
}
const render = (source: string) => md.render(source, fakeDocument) as FakeNode;

describe("message markdown", () => {
  it("keeps raw HTML as text and never builds elements from it", () => {
    const source = '<img src=x onerror="alert(1)"> and <script>alert(2)</script>';
    const root = render(source);
    expect(all(root, "IMG")).toHaveLength(0);
    expect(all(root, "SCRIPT")).toHaveLength(0);
    expect(root.textContent).toBe(source);
  });

  it("links only absolute https, http and mailto addresses", () => {
    for (const href of ["JaVaScRiPt:alert(1)", " javascript:alert(1)", "java\tscript:alert(1)", "//evil.com", "/relative", "data:text/html,<script>alert(1)</script>", "vbscript:msgbox(1)", "file:///etc/passwd", "https://user:pass@evil.com/", "https:", "evil.com"]) {
      expect(md.safeHref(href), href).toBeNull();
      const root = render(`[open](${href})`);
      expect(all(root, "A"), href).toHaveLength(0);
    }
    expect(md.safeHref("https://example.com/launch")).toBe("https://example.com/launch");
    expect(md.safeHref("http://example.com")).toBe("http://example.com/");
    expect(md.safeHref("mailto:hi@example.com")).toBe("mailto:hi@example.com");
    const [link] = all(render("I drafted it in [the shared doc](https://example.com/launch)."), "A");
    expect(link!.attributes).toMatchObject({ href: "https://example.com/launch", rel: "noopener noreferrer nofollow", target: "_blank" });
    expect(link!.textContent).toBe("the shared doc");
  });

  it("renders images as links and never loads them", () => {
    const root = render("![chart](https://example.com/chart.png) ![bad](javascript:alert(1))");
    expect(all(root, "IMG")).toHaveLength(0);
    const links = all(root, "A");
    expect(links).toHaveLength(1);
    expect(links[0]!.attributes.href).toBe("https://example.com/chart.png");
    expect(links[0]!.textContent).toBe("chart");
    expect(root.textContent).toContain("bad");
  });

  it("links bare web addresses without swallowing the sentence punctuation", () => {
    const [link] = all(render("See https://example.com/a_(b), then reply."), "A");
    expect(link!.attributes.href).toBe("https://example.com/a_(b)");
    expect(all(render("<https://example.com/x>"), "A")[0]!.attributes.href).toBe("https://example.com/x");
  });

  it("parses headings, emphasis, inline code, quotes and rules", () => {
    const blocks = md.parse("## What changed\n\nAsks **one** question, *0.1%* now, run `journalctl -f`.\n\n> Quote\n\n---\n\nsnake_case_name stays and 2 * 3 * 4 too");
    expect(blocks.map((block: { type: string }) => block.type)).toEqual(["heading", "paragraph", "quote", "rule", "paragraph"]);
    expect(blocks[0]).toMatchObject({ level: 2, children: [{ type: "text", text: "What changed" }] });
    expect(blocks[1].children.map((node: { type: string }) => node.type)).toEqual(["text", "strong", "text", "em", "text", "code", "text"]);
    expect(blocks[1].children[5].text).toBe("journalctl -f");
    expect(blocks[4].children).toEqual([{ type: "text", text: "snake_case_name stays and 2 * 3 * 4 too" }]);
    const root = render("## Title\n\nPara");
    expect(all(root, "H2")[0]!.dir).toBe("auto");
    expect(all(root, "P")[0]!.dir).toBe("auto");
  });

  it("keeps fenced code verbatim with a copy button", () => {
    const source = "Run:\n\n```bash\nsudo systemctl stop openstrudel\necho \"**not bold** <b>\"\n```\n\nDone.";
    const blocks = md.parse(source);
    expect(blocks[1]).toEqual({ type: "code", language: "bash", text: 'sudo systemctl stop openstrudel\necho "**not bold** <b>"' });
    const root = render(source);
    expect(all(root, "CODE")[0]!.textContent).toBe('sudo systemctl stop openstrudel\necho "**not bold** <b>"');
    expect(all(root, "BUTTON")).toHaveLength(1);
    expect(all(root, "PRE")[0]!.dir).toBe("ltr");
  });

  it("nests lists by indentation and keeps ordered starts", () => {
    const blocks = md.parse("- one\n  - two\n    - three\n- four\n\n3. third\n4. fourth");
    expect(blocks).toHaveLength(2);
    const [bullets, numbers] = blocks;
    expect(bullets).toMatchObject({ type: "list", ordered: false });
    expect(bullets.items).toHaveLength(2);
    const nested = bullets.items[0].blocks[1];
    expect(nested).toMatchObject({ type: "list", ordered: false });
    expect(nested.items[0].blocks[1]).toMatchObject({ type: "list" });
    expect(nested.items[0].blocks[1].items[0].blocks[0].children[0].text).toBe("three");
    expect(numbers).toMatchObject({ type: "list", ordered: true, start: 3 });
    expect(numbers.items.map((item: { blocks: { children: { text: string }[] }[] }) => item.blocks[0]!.children[0]!.text)).toEqual(["third", "fourth"]);
    const markers = all(render("3. third\n4. fourth"), "SPAN").filter((span) => span.className === "marker").map((span) => span.textContent);
    expect(markers).toEqual(["3.", "4."]);
  });

  it("parses tables and marks columns whose cells are all numbers", () => {
    const table = md.parse("| Venue | Capacity | Price | Distance |\n| --- | --- | --- | :-: |\n| Hangar 9 | 120 | €4,200 | 12 min |\n| The Glasshouse | 80 | €3,100 | 25 min |\n| Old Mill | 1 500 | -€5.6 | 8 min |")[0];
    expect(table.type).toBe("table");
    expect(table.header.map((cell: { text: string }[]) => cell[0]!.text)).toEqual(["Venue", "Capacity", "Price", "Distance"]);
    expect(table.rows).toHaveLength(3);
    expect(table.numeric).toEqual([false, true, true, false]);
    expect(table.align).toEqual([null, null, null, "center"]);
    // The same cases as native MessageContentTests: only plain figures, currency and percent count as numbers.
    const native = md.parse("| Venue | Capacity | Price | Share | Distance | Note |\n| --- | --- | --- | --- | --- | --- |\n| Hangar 9 | 120 | €4,200 | 12.5% | 12 min | |\n| Glasshouse | 1 200 | $3,100.50 | −3% | 25 min | |\n| Mill | | 5 600 ₽ | +0.1 % | — | |")[0];
    expect(native.numeric).toEqual([false, true, true, true, false, false]);
    const root = render("| a | b |\n|---|---|\n| x | 2 |");
    expect(all(root, "TH")).toHaveLength(2);
    expect(all(root, "TD")[1]!.className).toContain("numeric");
    expect(all(root, "TABLE")[0]!.style["--columns"]).toBe("2");
  });

  it("falls back to plain text above 100 000 characters", () => {
    const huge = "**bold** [link](https://example.com) ".repeat(30_000);
    const started = performance.now();
    const root = render(huge);
    expect(performance.now() - started).toBeLessThan(1000);
    expect(all(root, "A")).toHaveLength(0);
    expect(all(root, "STRONG")).toHaveLength(0);
    expect(root.textContent).toBe(huge);
  });

  it("parses a megabyte of hostile input in linear time", () => {
    const megabyte = 1024 * 1024;
    for (const unit of ["*a ", "**a", "_", "[", "[a](", "`", "``a", "~~", "<", "| a ", "> ", "- ", "  - ", "1. ", "![", "https://", "a\n"]) {
      const source = unit.repeat(Math.ceil(megabyte / unit.length)).slice(0, megabyte);
      const started = performance.now();
      md.parse(source);
      expect(performance.now() - started, JSON.stringify(unit)).toBeLessThan(2500);
    }
  });
});

describe("time clusters", () => {
  const at = (day: number, hours: number, minutes: number, seconds = 0) => new Date(2026, 9, day, hours, minutes, seconds).toISOString();
  it("starts a cluster on a new day or after a gap of 30 minutes", () => {
    const messages = [at(12, 9, 0), at(12, 9, 29, 59), at(12, 9, 59, 59), at(12, 10, 29, 58), at(13, 0, 1)].map((createdAt) => ({ createdAt }));
    expect(md.timeBreaks(messages).map((entry: { index: number }) => entry.index)).toEqual([0, 2, 4]);
  });
  it("shows the day only for imported history without an honest time", () => {
    const messages = [
      { createdAt: "2026-10-10T00:00:00.000Z", imported: true },
      { createdAt: "2026-10-10T00:00:00.000Z", imported: true },
      { createdAt: "2026-10-11T00:00:00.000Z", imported: false },
    ];
    const breaks = md.timeBreaks(messages);
    expect(breaks.map((entry: { index: number; hasTime: boolean }) => [entry.index, entry.hasTime])).toEqual([[0, false], [2, true]]);
    expect(breaks[0].date.getFullYear()).toBe(2026);
    expect(breaks[0].date.getMonth()).toBe(9);
    expect(breaks[0].date.getDate()).toBe(10);
  });
});
