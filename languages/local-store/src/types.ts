export type DID = string;

export interface ExpressionProof {
    signature: string;
    key: string;
    valid?: boolean;
    invalid?: boolean;
}

export interface Link {
    source: string;
    target: string;
    predicate?: string;
}

export interface LinkExpression {
    author: DID;
    timestamp: string;
    data: Link;
    proof: ExpressionProof;
    status?: string;
}

export interface PerspectiveDiff {
    additions: LinkExpression[];
    removals: LinkExpression[];
}

export interface Perspective {
    links: LinkExpression[];
}
