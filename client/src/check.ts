import { SuiGrpcClient } from "@mysten/sui/grpc";
import { DEPLOYER, UPGRADE_CAP_ID } from "./config.ts";
import { client } from "./client.ts"


// Balance: coin objects and address balance are reported saperately.
const { balance } = await client.getBalance({ owner: DEPLOYER });
console.log('total  :', balance.balance);
console.log('coins  :', balance.coinBalance);
console.log('address:', balance.addressBalance);

// The UpgradeCap should point at our package.
const { object } = await client.getObject({
    objectId: UPGRADE_CAP_ID,
    include: { json: true},
});
console.dir(object, {depth: 5 });