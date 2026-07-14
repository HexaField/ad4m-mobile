import { getStorage } from "./adapters.js";
import type { LinkExpression, PerspectiveDiff, Perspective } from "./types.js";

let _hashFn: ((data: string) => string) | null = null;

export function initStore(hashFn: (data: string) => string): void {
    _hashFn = hashFn;
}

function getHashFn(): (data: string) => string {
    if (!_hashFn) throw new Error("Store not initialized. Call initStore(hashFn) during init().");
    return _hashFn;
}

const REVISION_KEY = "revision";

function linkKey(h: string): string { return `links/${h}`; }
function sourceIdx(source: string, h: string): string { return `links-by-source/${source}/${h}`; }
function targetIdx(target: string, h: string): string { return `links-by-target/${target}/${h}`; }
function predIdx(pred: string, h: string): string { return `links-by-pred/${pred}/${h}`; }

export function hashLink(link: LinkExpression): string {
    return getHashFn()(JSON.stringify({
        source: link.data.source,
        predicate: link.data.predicate,
        target: link.data.target,
        author: link.author,
        timestamp: link.timestamp,
    }));
}

export function putLink(link: LinkExpression): string {
    const h = hashLink(link);
    const s = getStorage();
    s.put(linkKey(h), JSON.stringify(link));
    if (link.data.source) s.put(sourceIdx(link.data.source, h), h);
    if (link.data.target) s.put(targetIdx(link.data.target, h), h);
    if (link.data.predicate) s.put(predIdx(link.data.predicate, h), h);
    return h;
}

export function removeLink(link: LinkExpression): void {
    const h = hashLink(link);
    const s = getStorage();
    s.delete(linkKey(h));
    if (link.data.source) s.delete(sourceIdx(link.data.source, h));
    if (link.data.target) s.delete(targetIdx(link.data.target, h));
    if (link.data.predicate) s.delete(predIdx(link.data.predicate, h));
}

export function getLink(h: string): LinkExpression | null {
    const raw = getStorage().get(linkKey(h));
    return raw ? JSON.parse(raw) as LinkExpression : null;
}

export function applyDiff(diff: PerspectiveDiff): void {
    for (const link of diff.additions) putLink(link);
    for (const link of diff.removals) removeLink(link);
    bumpRevision();
}

export interface LinkQuery {
    source?: string;
    target?: string;
    predicate?: string;
}

export function queryLinks(query: LinkQuery): LinkExpression[] {
    const { source, target, predicate } = query;
    const s = getStorage();

    let hashes: string[];
    if (source) {
        hashes = s.listKeys(`links-by-source/${source}/`).map(k => s.get(k) || "").filter(Boolean);
    } else if (target) {
        hashes = s.listKeys(`links-by-target/${target}/`).map(k => s.get(k) || "").filter(Boolean);
    } else if (predicate) {
        hashes = s.listKeys(`links-by-pred/${predicate}/`).map(k => s.get(k) || "").filter(Boolean);
    } else {
        hashes = s.listKeys("links/").map(k => k.replace("links/", ""));
    }

    const seen = new Set<string>();
    const results: LinkExpression[] = [];
    for (const h of hashes) {
        if (seen.has(h)) continue;
        seen.add(h);
        const link = getLink(h);
        if (!link) continue;
        if (source && link.data.source !== source) continue;
        if (target && link.data.target !== target) continue;
        if (predicate && link.data.predicate !== predicate) continue;
        results.push(link);
    }
    return results;
}

export function allLinks(): Perspective {
    const keys = getStorage().listKeys("links/");
    const links: LinkExpression[] = [];
    for (const key of keys) {
        const raw = getStorage().get(key);
        if (raw) links.push(JSON.parse(raw) as LinkExpression);
    }
    return { links };
}

export function getRevision(): string | null {
    return getStorage().get(REVISION_KEY);
}

function bumpRevision(): void {
    const current = parseInt(getStorage().get(REVISION_KEY) || "0", 10);
    getStorage().put(REVISION_KEY, String(current + 1));
}
