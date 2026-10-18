module spending_vault::vault;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;

const ENotOwner: u64 = 0;
const ENotEnoughBalance: u64 = 1;
const EInvalidPeriod: u64 = 2;
const EAlreadyExpired: u64 = 3;

public struct Vault has key {
    id: UID,
    balance: Balance<SUI>,
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

public fun create(ctx: &mut TxContext): OwnerCap {
    let vault = Vault { id: object::new(ctx), balance: balance::zero() };
    let cap = OwnerCap {
        id: object::new(ctx),
        vault_id: object::id(&vault),
    };
    transfer::share_object(vault);
    cap
}

public fun vault_id(cap: &OwnerCap): ID { cap.vault_id }

public fun balance_value(vault: &Vault): u64 { vault.balance.value() }

public fun deposit(vault: &mut Vault, payment: Coin<SUI>) {
    vault.balance.join(payment.into_balance());
}

public fun withdraw(
    vault: &mut Vault,
    cap: &OwnerCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    //Only owner can withdraw otherwise abort
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
