#[test_only]
module spending_vault::vault_tests;

use spending_vault::vault::{Self, Vault, SpendCap};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;

const OWNER: address = @0xA;
const ONE_SUI: u64 = 1_000_000_000;
const AGENT: address = @0xB;
const DAY_MS: u64 = 86_400_000;
const START_MS: u64 = 1_000_000;

#[test]
fun create_links_cap_to_its_vault() {
    let mut scenario = test_scenario::begin(OWNER);

    // tx 1: OWNER creates a vault and receives the cap
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

    let coin = vault.withdraw(&cap, ONE_SUI / 2, scenario.ctx());
    assert!(coin.value() == ONE_SUI / 2);
    transfer::public_transfer(coin, OWNER);

    assert!(vault.balance_value() == ONE_SUI / 2);
    test_scenario::return_shared(vault);
    transfer::public_transfer(cap, OWNER);

    scenario.end();
}

#[test, expected_failure(abort_code = vault::ENotOwner)]
fun other_vault_cap_cannot_withdraw() {
    let mut scenario = test_scenario::begin(OWNER);

    let cap_a = vault::create(scenario.ctx());
    let cap_b = vault::create(scenario.ctx());

    scenario.next_tx(OWNER);

    let mut vault_a = scenario.take_shared_by_id<Vault>(cap_a.vault_id());

    let payment = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
    vault_a.deposit(payment);
    assert!(vault_a.balance_value() == ONE_SUI);

    let coin_withdraw = vault_a.withdraw(&cap_b, ONE_SUI, scenario.ctx());
    transfer::public_transfer(coin_withdraw, OWNER);

    test_scenario::return_shared(vault_a);

    transfer::public_transfer(cap_a, OWNER);
    transfer::public_transfer(cap_b, OWNER);

    scenario.end();
}

#[test, expected_failure(abort_code = vault::ENotEnoughBalance)]
fun cannot_withdraw_more_than_balance() {
    let mut scenario = test_scenario::begin(OWNER);

    let cap = vault::create(scenario.ctx());

    scenario.next_tx(OWNER);

    let mut vault = scenario.take_shared<Vault>();
    let payment = coin::mint_for_testing<SUI>(ONE_SUI / 2, scenario.ctx());
    vault.deposit(payment);

    let coin = vault.withdraw(&cap, ONE_SUI / 2 + 1, scenario.ctx());

    transfer::public_transfer(coin, OWNER);
    test_scenario::return_shared(vault);
    transfer::public_transfer(cap, OWNER);

    scenario.end();
}

#[test]
fun can_withdraw_full_balance() {
    let mut scenario = test_scenario::begin(OWNER);

    let cap = vault::create(scenario.ctx());

    scenario.next_tx(OWNER);

    let mut vault = scenario.take_shared<Vault>();
    let payment = coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
    vault.deposit(payment);

    let coin = vault.withdraw(&cap, ONE_SUI, scenario.ctx());
    assert!(coin.value() == ONE_SUI);
    assert!(vault.balance_value() == 0);

    transfer::public_transfer(coin, OWNER);
    test_scenario::return_shared(vault);
    transfer::public_transfer(cap, OWNER);

    scenario.end();
}

#[test]
fun issue_sends_cap_to_agent_with_rules() {
    let mut scenario = test_scenario::begin(OWNER);

    let owner_cap = vault::create(scenario.ctx());

    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);

    vault::issue_spend_cap(
        &owner_cap,
        AGENT,
        ONE_SUI,
        DAY_MS,
        START_MS + 7 * DAY_MS,
        &test_clock,
        scenario.ctx(),
    );

    scenario.next_tx(AGENT);
    let spend_cap = scenario.take_from_sender<SpendCap>();
    assert!(owner_cap.vault_id() == spend_cap.spend_cap_vault_id());
    assert!(spend_cap.limit_per_period() == ONE_SUI);
    assert!(spend_cap.period_ms() == DAY_MS);
    assert!(spend_cap.expires_at_ms() == START_MS + 7 * DAY_MS);
    assert!(spend_cap.spent_in_period() == 0);
    assert!(spend_cap.period_start_ms() == START_MS);

    scenario.return_to_sender(spend_cap);
    transfer::public_transfer(owner_cap, OWNER);
    test_clock.destroy_for_testing();

    scenario.end();
}
