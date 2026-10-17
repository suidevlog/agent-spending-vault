#[test_only]
module spending_vault::vault_tests;

use spending_vault::vault::{Self, Vault};
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;

const OWNER: address = @0xA;
const ONE_SUI: u64 = 1_000_000_000;

#[test]
fun create_links_cap_to_its_vault() {
    let mut scenario = test_scenario::begin(OWNER);

    // tx 1: OWNER creates a vault and recieves the cap
    let cap = vault::create(scenario.ctx());

    // tx 2: the shared vault is now visible
    scenario.next_tx(OWNER);
    let vault = scenario.take_shared<Vault>();

    assert!(cap.vault_id() == object::id(&vault));

    test_scenario::return_shared(vault);
    transfer::public_transfer(cap, OWNER);
    scenario.end();
}

#[test]
fun new_vault_starts_empty() {
    let mut scenario = test_scenario::begin(OWNER);

    let cap = vault::create(scenario.ctx());

    scenario.next_tx(OWNER);
    let vault = scenario.take_shared<Vault>();

    assert!(vault.balance_value() == 0);

    test_scenario::return_shared(vault);
    transfer::public_transfer(cap, OWNER);
    scenario.end();
}

#[test]
fun deposit_increases_balance() {
    let mut scenario = test_scenario::begin(OWNER);

    let cap = vault::create(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault>();

    let payment = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
    vault.deposit(payment);
    assert!(vault.balance_value() == ONE_SUI);

    test_scenario::return_shared(vault);
    transfer::public_transfer(cap, OWNER);
    scenario.end();
}

#[test]
fun owner_can_withdraw() {
    let mut scenario = test_scenario::begin(OWNER);

    let cap = vault::create(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault>();

    let payment = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
    vault.deposit(payment);
    assert!(vault.balance_value() == ONE_SUI);

    let coin = vault.withdraw(&cap, ONE_SUI/2, scenario.ctx());
    assert!(coin.value() == ONE_SUI / 2);
    transfer::public_transfer(coin, OWNER);

    assert!(vault.balance_value() == ONE_SUI / 2);
    test_scenario::return_shared(vault);
    transfer::public_transfer(cap, OWNER);

    scenario.end();
}
