import { client } from "./client.ts";
import { PACKAGE_ID } from "./config.ts";

// Every event our module has emitted, oldest first (the default order).
const page = await client.listEvents({
    filter: { eventType: `${PACKAGE_ID}::vault` },
    limit: 10,
});

for (const event of page.events) {
    console.log(event.eventType);
    console.log('   tx:', event.transactionDigest);
    console.dir(event.json, { depth: 4 });
}
console.log('more pages:', page.hasNextPage);