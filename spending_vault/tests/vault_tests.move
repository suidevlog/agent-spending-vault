#[test_only]
module spending_vault::vault_tests;

use spending_vault::vault::{Self, Vault};
use sui::accumulator_metadata::Owner;
use sui::test_scenario::{Self, Scenario};

const OWNER: address = @0xA;

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
