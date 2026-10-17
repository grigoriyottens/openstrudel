import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const html = readFileSync("deploy/invitations/connect.html", "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)![1]!;
const invitation = "openstrudel://connect?" + new URLSearchParams({host: "home.example", port: "7789", key: "a".repeat(64), pin: "b".repeat(64), name: "My Mac + phone"});
function open(fragment: string) {
  const nodes: Record<string, {hidden: boolean; textContent?: string; href?: string}> = {};
  const history: unknown[][] = [];
  vm.runInNewContext(script, {
    URL, Set, decodeURIComponent,
    document: {getElementById: (id: string) => nodes[id] ??= {hidden: true}},
    location: {hash: "#" + fragment, pathname: "/openstrudel/connect.html"},
    history: {replaceState: (...args: unknown[]) => history.push(args)},
    addEventListener: () => {},
  });
  return {nodes, history};
}

describe("Camera invitation fallback", () => {
  it("opens modern and legacy invitations and removes the secret from browser history", () => {
    for (const link of [invitation, invitation + "&keyPin=" + "c".repeat(64)]) {
      const {nodes, history} = open(encodeURIComponent(link));
      expect(nodes.open?.hidden).toBe(false);
      expect(nodes.open?.href).toBe(link);
      expect(nodes.title?.textContent).toContain("My Mac + phone");
      expect(history).toEqual([[null, "", "/openstrudel/connect.html"]]);
    }
  });
  it("rejects ambiguous destinations, credentials and unrelated deep links", () => {
    for (const link of [invitation + "&host=evil.example", invitation + "&key=" + "a".repeat(64),
      invitation.replace("home.example", "-home..example"), invitation.replace("7789", "0"),
      invitation.replace("connect?", "connect:443?"), invitation + "#unexpected",
      invitation + "&keyPin=weak", "openstrudel://oauth?code=test", "https://evil.example", "javascript:alert(1)"]) {
      const {nodes} = open(encodeURIComponent(link));
      expect(nodes.open?.hidden, link).toBe(true);
      expect(nodes.open?.href, link).toBeUndefined();
    }
    expect(open("%zz").nodes.open?.hidden).toBe(true);
  });
  it("has no analytics, external resources or automatic app navigation", () => {
    expect(html).toContain('name="referrer" content="no-referrer"');
    expect(html).toContain("default-src 'none'");
    expect(html).not.toMatch(/<script[^>]+src=|<img|fetch\(|location\.replace\(/);
  });
});
