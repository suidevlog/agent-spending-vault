module spending_vault::vault;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;

const ENotOwner: u64 = 0;
const ENotEnoughBalance: u64 = 1;

public struct Vault has key {
    id: UID,
    balance: Balance<SUI>,
}

public struct OwnerCap has key, store {
    id: UID,
    vault_id: ID,
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

public fun withdraw(vault: &mut Vault, cap: &OwnerCap, amount: u64, ctx: &mut TxContext): Coin<SUI> {
    
    //Only owner can withdraw otherwise abort
    assert!(cap.vault_id == object::id(vault), ENotOwner);
    // Balance has to be equal or more than withdrawal amount
    assert!(balance_value(vault) >= amount, ENotEnoughBalance);

    coin::take(&mut vault.balance, amount, ctx)
}
