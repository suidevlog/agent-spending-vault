module spending_vault::vault;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::dynamic_field as df;

const ENotOwner: u64 = 0;
const ENotEnoughBalance: u64 = 1;
const EInvalidPeriod: u64 = 2;
const EAlreadyExpired: u64 = 3;
const EWrongVault: u64 = 4;
const ECapExpired: u64 = 5;
const ELimitExceeded: u64 = 6;
const ECapRevoked: u64 = 7;

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
}

// One cap's rules and running totals, stored on the vault.
public struct CapRules has drop, store {
    limit_per_period: u64,
    period_ms: u64,
    spent_in_period: u64,
    period_start_ms: u64,
    expires_at_ms: u64,
}

// Dynamic-field key: the SpendCap's ID wrapped in its own type.
public struct CapKey(ID) has copy, drop, store;

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

public fun issue_spend_cap<T>(
    vault: &mut Vault<T>,
    owner_cap: &OwnerCap,
    agent: address,
    limit_per_period: u64,
    period_ms: u64,
    expires_at_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(owner_cap.vault_id == object::id(vault), ENotOwner);
    let now = clock.timestamp_ms();
    assert!(period_ms > 0, EInvalidPeriod);
    assert!(expires_at_ms > now, EAlreadyExpired);

    let spend_cap = SpendCap {
        id: object::new(ctx),
        vault_id: object::id(vault),
    };
    df::add(
        &mut vault.id,
        CapKey(object::id(&spend_cap)),
        CapRules {
            limit_per_period,
            period_ms,
            spent_in_period: 0,
            period_start_ms: now,
            expires_at_ms,
        },
    );

    transfer::transfer(spend_cap, agent);
}

// Owner kills a cap immediately. The agent still holds its SpendCap
// object, but the rules it points to are gone.
public fun revoke_spend_cap<T>(vault: &mut Vault<T>, owner_cap: &OwnerCap, cap_id: ID) {
    assert!(owner_cap.vault_id == object::id(vault), ENotOwner);
    assert!(df::exists(&vault.id, CapKey(cap_id)), ECapRevoked);
    let _rules: CapRules = df::remove(&mut vault.id, CapKey(cap_id));
}

public fun is_active<T>(vault: &Vault<T>, cap_id: ID): bool {
    df::exists(&vault.id, CapKey(cap_id))
}

fun rules<T>(vault: &Vault<T>, cap_id: ID): &CapRules {
    df::borrow(&vault.id, CapKey(cap_id))
}

public fun spend_cap_vault_id(cap: &SpendCap): ID { cap.vault_id }

public fun limit_per_period<T>(vault: &Vault<T>, cap_id: ID): u64 {
    rules(vault, cap_id).limit_per_period
}

public fun period_ms<T>(vault: &Vault<T>, cap_id: ID): u64 { rules(vault, cap_id).period_ms }

public fun spent_in_period<T>(vault: &Vault<T>, cap_id: ID): u64 {
    rules(vault, cap_id).spent_in_period
}

public fun period_start_ms<T>(vault: &Vault<T>, cap_id: ID): u64 {
    rules(vault, cap_id).period_start_ms
}

public fun expires_at_ms<T>(vault: &Vault<T>, cap_id: ID): u64 {
    rules(vault, cap_id).expires_at_ms
}

public fun spend<T>(
    vault: &mut Vault<T>,
    spend_cap: &SpendCap,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    let now = clock.timestamp_ms();

    // The cap must belong to this vault.
    assert!(spend_cap.vault_id == object::id(vault), EWrongVault);

    // A revoked cap has no rules on the vault.
    assert!(df::exists(&vault.id, CapKey(object::id(spend_cap))), ECapRevoked);

    let rules: &mut CapRules = df::borrow_mut(&mut vault.id, CapKey(object::id(spend_cap)));

    // at exactly expires_at_ms, the cap is dead.
    assert!(now < rules.expires_at_ms, ECapExpired);

    // If a full period has passed, start a new one. This must happen
    // BEFORE the limit check, or yesterday's spending blocks today's.
    if (now >= rules.period_start_ms + rules.period_ms) {
        rules.spent_in_period = 0;
        rules.period_start_ms = now;
    };

    // Spending up to exactly the limit is allowed (<=)
    assert!(amount <= rules.limit_per_period - rules.spent_in_period, ELimitExceeded);

    // Record the spend. If the balance check below aborts, the whole
    // transaction reverts, so this write never persists on failure.
    rules.spent_in_period = rules.spent_in_period + amount;

    // 'rules' is no longer used, so the mutable borrow of vault.id has ended
    // and we may borrow the whole vault again.
    assert!(vault.balance_value() >= amount, ENotEnoughBalance);
    coin::take(&mut vault.balance, amount, ctx)
}
