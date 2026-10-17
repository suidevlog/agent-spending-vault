module spending_vault::vault;

use sui::balance::{Self, Balance};
use sui::sui::SUI;

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
