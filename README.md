# Agenti Spending Vault

A Sui smart contract where an owner deposits SUI into a vault and give other addresses (like an AI agent) limited permission to spend from it - with daily limits, expiry times, and instant revocation.

## Status

- [x] V0 - Project setup
- [ ] V1 - Vault, owner withdraw, one spend capability with limit and expiry
- [ ] V2 - Multiple capabilites, revocation, recipient allowlist, events, any coin type
- [ ] V3 - TypeScript client and autonomous agent script, sponsored gas
- [ ] v4 - Web frontend with zkLogin

## Build & test

Requires: Sui CLI 1.81+

    cd spending_vault
    sui move build
    sui move test

## Liscense

MIT