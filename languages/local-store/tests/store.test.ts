import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

import { initStorage } from "../src/adapters.js";
import type { StorageAdapter } from "../src/adapters.js";
import * as store from "../src/store.js";
import type { LinkExpression, PerspectiveDiff } from "../src/types.js";

class MemoryStorage implements StorageAdapter {
    private data = new Map<string, string>();
    get(key: string): string | null { return this.data.get(key) ?? null; }
    put(key: string, value: string): void { this.data.set(key, value); }
    delete(key: string): void { this.data.delete(key); }
    listKeys(prefix?: string): string[] {
        const keys = [...this.data.keys()];
        return prefix ? keys.filter(k => k.startsWith(prefix)) : keys;
    }
}

function testHash(data: string): string {
    return createHash("sha256").update(data).digest("hex").slice(0, 16);
}

function makeLink(source: string, target: string, predicate?: string): LinkExpression {
    return {
        author: "did:test:alice",
        timestamp: new Date().toISOString(),
        data: { source, target, predicate },
        proof: { signature: "test", key: "test" },
    };
}

describe("local-store", () => {
    beforeEach(() => {
        initStorage(new MemoryStorage());
        store.initStore(testHash);
    });

    it("stores and retrieves a link", () => {
        const link = makeLink("a", "b", "knows");
        store.putLink(link);
        const all = store.allLinks();
        assert.equal(all.links.length, 1);
        assert.equal(all.links[0].data.source, "a");
        assert.equal(all.links[0].data.target, "b");
    });

    it("removes a link", () => {
        const link = makeLink("a", "b");
        store.putLink(link);
        assert.equal(store.allLinks().links.length, 1);
        store.removeLink(link);
        assert.equal(store.allLinks().links.length, 0);
    });

    it("queries by source", () => {
        store.putLink(makeLink("a", "b"));
        store.putLink(makeLink("a", "c"));
        store.putLink(makeLink("x", "y"));
        const results = store.queryLinks({ source: "a" });
        assert.equal(results.length, 2);
    });

    it("queries by target", () => {
        store.putLink(makeLink("a", "b"));
        store.putLink(makeLink("c", "b"));
        store.putLink(makeLink("x", "y"));
        const results = store.queryLinks({ target: "b" });
        assert.equal(results.length, 2);
    });

    it("queries by predicate", () => {
        store.putLink(makeLink("a", "b", "knows"));
        store.putLink(makeLink("c", "d", "likes"));
        store.putLink(makeLink("e", "f", "knows"));
        const results = store.queryLinks({ predicate: "knows" });
        assert.equal(results.length, 2);
    });

    it("queries with multiple filters", () => {
        store.putLink(makeLink("a", "b", "knows"));
        store.putLink(makeLink("a", "c", "knows"));
        store.putLink(makeLink("a", "b", "likes"));
        const results = store.queryLinks({ source: "a", target: "b" });
        assert.equal(results.length, 2);
    });

    it("returns all links with empty query", () => {
        store.putLink(makeLink("a", "b"));
        store.putLink(makeLink("c", "d"));
        const results = store.queryLinks({});
        assert.equal(results.length, 2);
    });

    it("applyDiff adds and removes", () => {
        const link1 = makeLink("a", "b");
        const link2 = makeLink("c", "d");
        store.putLink(link1);
        store.putLink(link2);

        const diff: PerspectiveDiff = {
            additions: [makeLink("e", "f")],
            removals: [link1],
        };
        store.applyDiff(diff);

        const all = store.allLinks();
        assert.equal(all.links.length, 2);
        const sources = all.links.map(l => l.data.source).sort();
        assert.deepEqual(sources, ["c", "e"]);
    });

    it("bumps revision on applyDiff", () => {
        assert.equal(store.getRevision(), null);

        store.applyDiff({ additions: [makeLink("a", "b")], removals: [] });
        assert.equal(store.getRevision(), "1");

        store.applyDiff({ additions: [makeLink("c", "d")], removals: [] });
        assert.equal(store.getRevision(), "2");
    });
});
