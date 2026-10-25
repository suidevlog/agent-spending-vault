module spending_vault::vault;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};

const ENotOwner: u64 = 0;
const ENotEnoughBalance: u64 = 1;
const EInvalidPeriod: u64 = 2;
const EAlreadyExpired: u64 = 3;
const EWrongVault: u64 = 4;
const ECapExpired: u64 = 5;
const ELimitExceeded: u64 = 6;

public struct Vault<phantom T> has key {
    id: UID,
    balance: Balance<T>,
}

public struct OwnerCap has key, store {
    id: UID,
    vault_id: ID,
}

public struct SpendCap has key {
    id: UID,
    vault_id: ID,
    limit_per_period: u64,
    period_ms: u64,
    spent_in_period: u64,
    period_start_ms: u64,
    expires_at_ms: u64,
}

public fun create<T>(ctx: &mut TxContext): OwnerCap {
    let vault = Vault { id: object::new(ctx), balance: balance::zero<T>() };
    let cap = OwnerCap {
        id: object::new(ctx),
        vault_id: object::id(&vault),
    };
    transfer::share_object(vault);
    cap
}

public fun vault_id(cap: &OwnerCap): ID { cap.vault_id }

public fun balance_value<T>(vault: &Vault<T>): u64 { vault.balance.value() }

public fun deposit<T>(vault: &mut Vault<T>, payment: Coin<T>) {
    vault.balance.join(payment.into_balance());
}

public fun withdraw<T>(
    vault: &mut Vault<T>,
    cap: &OwnerCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    // Only owner can withdraw otherwise abort
    assert!(cap.vault_id == object::id(vault), ENotOwner);
    // Balance has to be equal or more than withdrawal amount
    assert!(balance_value(vault) >= amount, ENotEnoughBalance);

    coin::take(&mut vault.balance, amount, ctx)
}

public fun issue_spend_cap(
    owner_cap: &OwnerCap,
    agent: address,
    limit_per_period: u64,
    period_ms: u64,
    expires_at_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let now = clock.timestamp_ms();
    assert!(period_ms > 0, EInvalidPeriod);
    assert!(expires_at_ms > now, EAlreadyExpired);

    let spend_cap = SpendCap {
        id: object::new(ctx),
        vault_id: owner_cap.vault_id,
        limit_per_period,
        period_ms,
        spent_in_period: 0,
        period_start_ms: now,
        expires_at_ms,
    };

    transfer::transfer(spend_cap, agent);
}

public fun spend_cap_vault_id(cap: &SpendCap): ID { cap.vault_id }

public fun limit_per_period(cap: &SpendCap): u64 { cap.limit_per_period }

public fun period_ms(cap: &SpendCap): u64 { cap.period_ms }

public fun spent_in_period(cap: &SpendCap): u64 { cap.spent_in_period }

public fun period_start_ms(cap: &SpendCap): u64 { cap.period_start_ms }

public fun expires_at_ms(cap: &SpendCap): u64 { cap.expires_at_ms }

public fun spend<T>(
    vault: &mut Vault<T>,
    spend_cap: &mut SpendCap,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    let now = clock.timestamp_ms();

    // The cap must belong to this vault. Without this, an agent with a cap
    // for an empty vault could spend from any other vault.
    assert!(spend_cap.vault_id == object::id(vault), EWrongVault);

    // The cap must not be expired. Same boundary as issue_spend_cap:
    // at exactly expires_at_ms, the cap is dead.
    assert!(now < spend_cap.expires_at_ms, ECapExpired);

    // If a full period has passed, start a new one. This must happen
    // BEFORE the limit check, or yesterday's spending blocks today's.
    if (now >= spend_cap.period_start_ms + spend_cap.period_ms) {
        spend_cap.spent_in_period = 0;
        spend_cap.period_start_ms = now;
    };

    // Spending up to exactly the limit is allowed (<=)
    assert!(amount <= spend_cap.limit_per_period - spend_cap.spent_in_period, ELimitExceeded);

    // The vault must hold enough. Our own error code tells the agent
    // exactly why it failed, instead of a generic framework error.
    assert!(vault.balance_value() >= amount, ENotEnoughBalance);

    // All checks passed: record the spend, then release the coin.
    spend_cap.spent_in_period = spend_cap.spent_in_period + amount;
    coin::take(&mut vault.balance, amount, ctx)
}
