import {
    storageGet,
    storagePut,
    storageDelete,
    storageListKeys,
} from "@coasys/ad4m-ldk";

import type { StorageAdapter } from "./adapters.js";

export class DenoStorageAdapter implements StorageAdapter {
    get(key: string): string | null {
        return storageGet(key);
    }

    put(key: string, value: string): void {
        storagePut(key, value);
    }

    delete(key: string): void {
        storageDelete(key);
    }

    listKeys(prefix?: string): string[] {
        return storageListKeys(prefix);
    }
}
