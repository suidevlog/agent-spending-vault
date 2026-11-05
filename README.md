# Agent Spending Vault

A Sui Move package where an owner deposits any coin type into a shared vault
and gives other addresses (such as AI agents) limited permission to spend
from it: per-period limits, expiry, optional recipient allowlists, and
instant revocation.

## Status

- [x] V0 - Project setup
- [x] V1 - Vault, owner withdraw, one spend capability with limit and expiry
- [x] V2 - Multiple capabilities, revocation, recipient allowlist, events, any coin type
- [ ] V3 - TypeScript client and autonomous agent script, sponsored gas
- [ ] V4 - Web frontend with zkLogin

## How it works

- `Vault<T>`: shared object holding a `Balance<T>`. Anyone can deposit.
- `OwnerCap`: returned by `create<T>`. Withdraws, issues and revokes spend
  caps, and manages allowlists.
- `SpendCap`: sent to an agent. It has no `store`, so the agent cannot hand
  it off. It only points at its rules, which live on the vault as a dynamic
  field keyed by the cap's ID.
- Rules per cap: limit per period (in the coin's smallest unit, e.g. MIST),
  period length in ms, expiry in ms, optional recipient allowlist.

### Spending

- `spend` returns a `Coin<T>` to the caller's PTB. Unrestricted caps only.
- `spend_to` pays a recipient inside the module. Required for caps with an
  allowlist, because a returned coin could be sent anywhere.

Checks run in this order: cap belongs to vault, not revoked, not expired,
recipient allowed, within limit, vault has enough balance.

### Revocation

`revoke_spend_cap` removes a cap's rules from the vault. The vault is a
shared object, so every spend ordered after the revocation aborts with
`ECapRevoked`. The agent's cooperation is not needed.

## Events

| Event | Emitted by |
|---|---|
| `VaultCreated<T>` | `create` |
| `Deposited<T>` | `deposit` |
| `Withdrawn<T>` | `withdraw` |
| `SpendCapIssued<T>` | `issue_spend_cap` (carries the new `cap_id`) |
| `SpendCapRevoked` | `revoke_spend_cap` |
| `AllowlistSet` | `set_allowlist` |
| `AllowlistCleared` | `clear_allowlist` |
| `Spent<T>` | `spend`, `spend_to` (recipient is none for `spend`) |

Events with an amount carry the coin type.

## Error codes

| Code | Name | Meaning |
|---|---|---|
| 0 | `ENotOwner` | `OwnerCap` does not belong to this vault |
| 1 | `ENotEnoughBalance` | Vault holds less than the amount |
| 2 | `EInvalidPeriod` | Period is 0 |
| 3 | `EAlreadyExpired` | Expiry is not in the future at issue time |
| 4 | `EWrongVault` | `SpendCap` belongs to another vault |
| 5 | `ECapExpired` | Cap is at or past its expiry |
| 6 | `ELimitExceeded` | Amount exceeds what is left in this period |
| 7 | `ECapRevoked` | Cap was revoked (or the ID is unknown) |
| 8 | `ERecipientNotAllowed` | Recipient is not on the cap's allowlist |
| 9 | `ERestrictedCap` | `spend` called on a cap with an allowlist |
| 10 | `EEmptyAllowlist` | `set_allowlist` called with an empty list |

## Deployments

| Network | Package ID | Built from |
|---|---|---|
| testnet | `0x408397699192297855badb18c10e20b5d3395052decd8a6742587ab4d5eee3e8` | tag `v2` |

UpgradeCap (owned by the deployer):
`0x95f816004e3153a1dd583cc3f42b31b0b7fc383cf2a87afee8a481e4eb88d9a5`

## Build & test

Requires: Sui CLI 1.82+

    cd spending_vault
    sui move build
    sui move test

## License

MIT