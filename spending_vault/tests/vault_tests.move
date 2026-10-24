#[test_only]
module spending_vault::vault_tests;

use spending_vault::vault::{Self, Vault, OwnerCap, SpendCap};
use sui::clock::{Self, Clock};
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

const OWNER: address = @0xA;
const ONE_SUI: u64 = 1_000_000_000;
const AGENT: address = @0xB;
const DAY_MS: u64 = 86_400_000;
const START_MS: u64 = 1_000_000;

// Shared setup: avault holding 10 SUI, and a spend cap for AGENT with
// a limit of 1 SUI per day, expiring 7 days after START_MS.
// Ends in a fresh transaction as AGENT, ready to spend.
fun setup(scenario: &mut Scenario, clock: &Clock): OwnerCap {
    let owner_cap = vault::create(scenario.ctx());
    vault::issue_spend_cap(
        &owner_cap,
        AGENT,
        ONE_SUI,
        DAY_MS,
        START_MS + 7 * DAY_MS,
        clock,
        scenario.ctx(),
    );
    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault>();
    vault.deposit(coin::mint_for_testing(10 * ONE_SUI, scenario.ctx()));
    test_scenario::return_shared(vault);

    scenario.next_tx(AGENT);
    owner_cap
}

// Shared cleanup: every object goes back or away, so no test can forget one.
fun cleanup(
    scenario: Scenario,
    vault: Vault,
    spend_cap: SpendCap,
    owner_cap: OwnerCap,
    test_clock: Clock,
) {
    test_scenario::return_shared(vault);
    scenario.return_to_sender(spend_cap);
    transfer::public_transfer(owner_cap, OWNER);
    test_clock.destroy_for_testing();
    scenario.end();
}

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

// The normal case: spending under the limit works, and all three
// results change correctly - the coin, the cap's record, the vault.
#[test]
fun agent_can_spend_within_limit() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    let mut vault = scenario.take_shared<Vault>();
    let mut spend_cap = scenario.take_from_sender<SpendCap>();

    let coin = vault.spend(&mut spend_cap, ONE_SUI / 2, &test_clock, scenario.ctx());
    assert!(coin.value() == ONE_SUI / 2);
    assert!(spend_cap.spent_in_period() == ONE_SUI / 2);
    assert!(vault.balance_value() == 10 * ONE_SUI - ONE_SUI / 2);

    transfer::public_transfer(coin, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Limit voundary, outside: one MIST over the limit must fail.
#[test, expected_failure(abort_code = vault::ELimitExceeded)]
fun cannot_spend_over_limit() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    let mut vault = scenario.take_shared<Vault>();
    let mut spend_cap = scenario.take_from_sender<SpendCap>();

    let coin = vault.spend(&mut spend_cap, ONE_SUI + 1, &test_clock, scenario.ctx());

    transfer::public_transfer(coin, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Reset boundary, outside: one millisecond BEFORE the period ends,
// the old spending still counts, so even 1 MIST more must fail.

#[test, expected_failure(abort_code = vault::ELimitExceeded)]
fun limit_does_not_reset_before_period_ends() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    let mut vault = scenario.take_shared<Vault>();
    let mut spend_cap = scenario.take_from_sender<SpendCap>();

    let first = vault.spend(&mut spend_cap, ONE_SUI, &test_clock, scenario.ctx());
    transfer::public_transfer(first, AGENT);

    test_clock.set_for_testing(START_MS + DAY_MS - 1);
    let second = vault.spend(&mut spend_cap, 1, &test_clock, scenario.ctx());

    transfer::public_transfer(second, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Reset boundary inside: at Exactly one period later, a fresh period
// begins. This also proves spending exactly the limit is allowed (<=)
#[test]
fun limit_resets_after_period() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    let mut vault = scenario.take_shared<Vault>();
    let mut spend_cap = scenario.take_from_sender<SpendCap>();

    let first = vault.spend(&mut spend_cap, ONE_SUI, &test_clock, scenario.ctx());
    transfer::public_transfer(first, AGENT);

    test_clock.set_for_testing(START_MS + DAY_MS);
    let second = vault.spend(&mut spend_cap, ONE_SUI, &test_clock, scenario.ctx());
    assert!(second.value() == ONE_SUI);
    assert!(spend_cap.spent_in_period() == ONE_SUI);
    assert!(spend_cap.period_start_ms() == START_MS + DAY_MS);

    transfer::public_transfer(second, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

//Expiry boundary: at EXACTLY expires_at_ms the cap is dead.
#[test, expected_failure(abort_code = vault::ECapExpired)]
fun cannot_spend_at_expiry() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    let mut vault = scenario.take_shared<Vault>();
    let mut spend_cap = scenario.take_from_sender<SpendCap>();

    test_clock.set_for_testing(START_MS + 7 * DAY_MS);
    let coin = vault.spend(&mut spend_cap, 1, &test_clock, scenario.ctx());

    transfer::public_transfer(coin, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock)
}

// Security: a cap for vault A must not spend from vault B.
#[test, expected_failure(abort_code = vault::EWrongVault)]
fun cap_cannot_spend_from_other_vault() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    // A second vault, B that agent's cap was never issued for.
    let other_owner_cap = vault::create(scenario.ctx());
    scenario.next_tx(AGENT);

    let mut other_vault = scenario.take_shared_by_id<Vault>(other_owner_cap.vault_id());
    other_vault.deposit(coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx()));
    let mut spend_cap = scenario.take_from_sender<SpendCap>();

    let coin = other_vault.spend(&mut spend_cap, 1, &test_clock, scenario.ctx());

    transfer::public_transfer(coin, AGENT);
    transfer::public_transfer(other_owner_cap, OWNER);
    cleanup(scenario, other_vault, spend_cap, owner_cap, test_clock);
}
