import {
    defineLanguage,
    agentDid,
    hash,
    emitPerspectiveDiff,
} from "@coasys/ad4m-ldk";

import type { PerspectiveDiff } from "./src/types.js";
import * as store from "./src/store.js";
import { initStorage } from "./src/adapters.js";
import { DenoStorageAdapter } from "./src/adapters-deno.js";

let myDid = "";
let localAgents: string[] = [];

const language = defineLanguage({
    name: "local-store",
    version: "0.1.0",
    isPublic: false,

    async init() {
        initStorage(new DenoStorageAdapter());
        store.initStore(hash);
        myDid = agentDid();
        localAgents = [myDid];
        console.log(`[local-store] init: did=${myDid}`);
    },

    async teardown() {
        myDid = "";
        localAgents = [];
    },

    commit: {
        async commit(diff: PerspectiveDiff) {
            store.applyDiff(diff);
            emitPerspectiveDiff(diff);
        },
    },

    sync: {
        async sync() {
            return { additions: [], removals: [] };
        },

        async render() {
            return store.allLinks();
        },

        async currentRevision() {
            return store.getRevision() || "";
        },
    },

    query: {
        supportedKinds() {
            return ["link-pattern"];
        },

        async run(req: { kind: string; payload: unknown }) {
            if (req.kind !== "link-pattern") {
                return { kind: "error", payload: `Unsupported query kind: ${req.kind}` };
            }
            const pattern = req.payload as {
                source?: string;
                target?: string;
                predicate?: string;
            };
            return { kind: "links", payload: store.queryLinks(pattern) };
        },
    },

    peers: {
        setLocal(agents: string[]) {
            localAgents = agents;
        },

        async remote() {
            return [];
        },
    },
});

export const {
    name,
    version,
    isPublic,
    init,
    teardown,
    perspectiveCommit,
    perspectiveSyncSync,
    perspectiveSyncRender,
    perspectiveSyncCurrentRevision,
    perspectiveQuerySupportedKinds,
    perspectiveQueryRun,
    peersSetLocal,
    peersRemote,
} = language;

export default language;
