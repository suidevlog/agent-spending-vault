import { client } from "./client.ts";

const digest = process.argv[2];
if (!digest) throw new Error('usage: npm run inspect-tx -- <digest>');

const result = await client.getTransaction({
    digest,
    include: { event: true, objectTypes: true },
});

const tx = result.Transaction ?? result.FailedTransaction;

console.log('success:', tx.status.success);
console.log('checkpoint:', tx.checkpoint, 'time:', tx.timestampMs);
console.dir(tx.events, { depth: 6 });
console.dir(tx.objectTypes, { depth: 4 });
