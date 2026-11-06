import { SuiGrpcClient } from "@mysten/sui/grpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import { DEPLOYER, PACKAGE_ID } from "./config.ts";
import { client } from "./client.ts";

const secret = process.env.SUI_PRIVATE_KEY;
if (!secret) throw new Error('SUI_PRIVATE_KEY missing: run with --env-file=.env')

const keypair = Ed25519Keypair.fromSecretKey(secret);
const sender = keypair.toSuiAddress();
if (sender !== DEPLOYER) {
    throw new Error('key belongs to ${sender}, expected DEPLOYER ${DEPLOYER}');
}

const tx = new Transaction();
const ownerCap = tx.moveCall({
    target: `${PACKAGE_ID}::vault::create`,
    typeArguments: ['0x2::sui::SUI'],
});
tx.transferObjects([ownerCap], sender);

const result = await client.signAndExecuteTransaction({
    transaction: tx,
    signer: keypair,
    include: { effects: true, enents: true },
});

// A Move abort does NOT throw; it comes back as FailedTransaction.
if (result.$kind === 'FailedTransaction') {
    throw new Error(result.FailedTransaction.status.error?.message ?? 'transaction failed');
}
console.log('digest:', result.Transaction.digest);