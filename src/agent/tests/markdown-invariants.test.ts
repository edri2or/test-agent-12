import { readFileSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = join(__dirname, "..", "..", "..");

function readDocLines(relPath: string): string[] {
  return readFileSync(join(REPO_ROOT, relPath), "utf8").split("\n");
}

function rowsAfterClaim(lines: string[], claimLineIdx: number): number {
  let i = claimLineIdx + 1;
  while (i < lines.length && !lines[i].startsWith("|")) i++;
  if (i >= lines.length) return -1;
  i += 2;
  let count = 0;
  while (i < lines.length && lines[i].startsWith("|")) {
    count++;
    i++;
  }
  return count;
}

function findClaimLine(
  lines: string[],
  pattern: RegExp,
): { idx: number; claimed: number } | null {
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(pattern);
    if (m) {
      return { idx: i, claimed: parseInt(m[1], 10) };
    }
  }
  return null;
}

describe("markdown invariants", () => {
  test("docs/bootstrap-state.md: 'N secrets present' claim matches inventory table row count", () => {
    const lines = readDocLines("docs/bootstrap-state.md");
    const claim = findClaimLine(lines, /^(\d+)\s+secrets present/);
    expect(claim).not.toBeNull();
    if (!claim) return;

    const actualRows = rowsAfterClaim(lines, claim.idx);
    expect(actualRows).toBe(claim.claimed);
  });
});
