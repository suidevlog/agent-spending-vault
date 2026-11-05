#[test_only]
module spending_vault::vault_tests;

use spending_vault::vault::{
    Self,
    Vault,
    OwnerCap,
    SpendCap,
    VaultCreated,
    Deposited,
    Withdrawn,
    SpendCapIssued,
    SpendCapRevoked,
    AllowlistSet,
    AllowlistCleared,
    Spent,
};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

const OWNER: address = @0xA;
const ONE_SUI: u64 = 1_000_000_000;
const AGENT: address = @0xB;
const AGENT_2: address = @0xc;
const RECIPIENT: address = @0xD;
const OTHER: address = @0xE;
const DAY_MS: u64 = 86_400_000;
const START_MS: u64 = 1_000_000;

// A coin type shaped like SUI: drop only, no store. If 'phantom' were
// removed from Vault, Vault<TEST_USD> would lose 'key' and this file
// would not compile
public struct TEST_USD has drop {}

// Shared setup: a vault holding 10 SUI, and a spend cap for AGENT with
// a limit of 1 SUI per day, expiring 7 days after START_MS.
// Ends in a fresh transaction as AGENT, ready to spend.
fun setup(scenario: &mut Scenario, clock: &Clock): OwnerCap {
    let owner_cap = vault::create<SUI>(scenario.ctx());

    // The vault is shared at the end of this tx; take it in the next one.
    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    vault.deposit(coin::mint_for_testing(10 * ONE_SUI, scenario.ctx()));
    vault.issue_spend_cap(
        &owner_cap,
        AGENT,
        ONE_SUI,
        DAY_MS,
        START_MS + 7 * DAY_MS,
        clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(vault);

    scenario.next_tx(AGENT);
    owner_cap
}

// Shared cleanup: every object goes back or away, so no test can forget one.
fun cleanup(
    scenario: Scenario,
    vault: Vault<SUI>,
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

// The ID of the most recent SpendCap sent to 'agent'.
fun cap_id_of(agent: address): ID {
    test_scenario::most_recent_id_for_address<SpendCap>(agent).destroy_some()
}

// Starts a fresh tx as OWNER and revokes 'cap_id' on the SUI vault.
fun revoke_as_owner(scenario: &mut Scenario, owner_cap: &OwnerCap, cap_id: ID) {
    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    vault.revoke_spend_cap(owner_cap, cap_id);
    test_scenario::return_shared(vault);
}

// Starts a fresh tx as OWNER and restricts `cap_id` to `recipients`.
fun set_allowlist_as_owner(
    scenario: &mut Scenario,
    owner_cap: &OwnerCap,
    cap_id: ID,
    recipients: vector<address>,
) {
    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    vault.set_allowlist(owner_cap, cap_id, recipients);
    test_scenario::return_shared(vault);
}

#[test]
fun create_links_cap_to_its_vault() {
    let mut scenario = test_scenario::begin(OWNER);

    // tx 1: OWNER creates a vault and receives the cap
    let cap = vault::create<SUI>(scenario.ctx());

    // tx 2: the shared vault is now visible
    scenario.next_tx(OWNER);
    let vault = scenario.take_shared<Vault<SUI>>();

    assert!(cap.vault_id() == object::id(&vault));

    test_scenario::return_shared(vault);
    transfer::public_transfer(cap, OWNER);
    scenario.end();
}

#[test]
fun new_vault_starts_empty() {
    let mut scenario = test_scenario::begin(OWNER);

    let cap = vault::create<SUI>(scenario.ctx());

    scenario.next_tx(OWNER);
    let vault = scenario.take_shared<Vault<SUI>>();

    assert!(vault.balance_value() == 0);

    test_scenario::return_shared(vault);
    transfer::public_transfer(cap, OWNER);
    scenario.end();
}

#[test]
fun deposit_increases_balance() {
    let mut scenario = test_scenario::begin(OWNER);

    let cap = vault::create<SUI>(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();

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

    let cap = vault::create<SUI>(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();

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

    let cap_a = vault::create<SUI>(scenario.ctx());
    let cap_b = vault::create<SUI>(scenario.ctx());

    scenario.next_tx(OWNER);

    let mut vault_a = scenario.take_shared_by_id<Vault<SUI>>(cap_a.vault_id());

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

    let cap = vault::create<SUI>(scenario.ctx());

    scenario.next_tx(OWNER);

    let mut vault = scenario.take_shared<Vault<SUI>>();
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

    let cap = vault::create<SUI>(scenario.ctx());

    scenario.next_tx(OWNER);

    let mut vault = scenario.take_shared<Vault<SUI>>();
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
    let owner_cap = vault::create<SUI>(scenario.ctx());
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    vault.issue_spend_cap(
        &owner_cap,
        AGENT,
        ONE_SUI,
        DAY_MS,
        START_MS + 7 * DAY_MS,
        &test_clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(vault);

    scenario.next_tx(AGENT);
    let vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    let cap_id = object::id(&spend_cap);

    assert!(owner_cap.vault_id() == spend_cap.spend_cap_vault_id());
    assert!(vault.limit_per_period(cap_id) == ONE_SUI);
    assert!(vault.period_ms(cap_id) == DAY_MS);
    assert!(vault.expires_at_ms(cap_id) == START_MS + 7 * DAY_MS);
    assert!(vault.spent_in_period(cap_id) == 0);
    assert!(vault.period_start_ms(cap_id) == START_MS);

    test_scenario::return_shared(vault);
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

    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();

    let coin = vault.spend(&spend_cap, ONE_SUI / 2, &test_clock, scenario.ctx());
    assert!(coin.value() == ONE_SUI / 2);
    assert!(vault.spent_in_period(object::id(&spend_cap)) == ONE_SUI / 2);
    assert!(vault.balance_value() == 10 * ONE_SUI - ONE_SUI / 2);

    transfer::public_transfer(coin, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Limit Boundary, outside: one MIST over the limit must fail.
#[test, expected_failure(abort_code = vault::ELimitExceeded)]
fun cannot_spend_over_limit() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();

    let coin = vault.spend(&spend_cap, ONE_SUI + 1, &test_clock, scenario.ctx());

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

    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();

    let first = vault.spend(&spend_cap, ONE_SUI, &test_clock, scenario.ctx());
    transfer::public_transfer(first, AGENT);

    test_clock.set_for_testing(START_MS + DAY_MS - 1);
    let second = vault.spend(&spend_cap, 1, &test_clock, scenario.ctx());

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

    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();

    let first = vault.spend(&spend_cap, ONE_SUI, &test_clock, scenario.ctx());
    transfer::public_transfer(first, AGENT);

    test_clock.set_for_testing(START_MS + DAY_MS);
    let second = vault.spend(&spend_cap, ONE_SUI, &test_clock, scenario.ctx());
    assert!(second.value() == ONE_SUI);
    assert!(vault.spent_in_period(object::id(&spend_cap)) == ONE_SUI);
    assert!(vault.period_start_ms(object::id(&spend_cap)) == START_MS + DAY_MS);

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

    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();

    test_clock.set_for_testing(START_MS + 7 * DAY_MS);
    let coin = vault.spend(&spend_cap, 1, &test_clock, scenario.ctx());

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
    let other_owner_cap = vault::create<SUI>(scenario.ctx());
    scenario.next_tx(AGENT);

    let mut other_vault = scenario.take_shared_by_id<Vault<SUI>>(other_owner_cap.vault_id());
    other_vault.deposit(coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx()));
    let spend_cap = scenario.take_from_sender<SpendCap>();

    let coin = other_vault.spend(&spend_cap, 1, &test_clock, scenario.ctx());

    transfer::public_transfer(coin, AGENT);
    transfer::public_transfer(other_owner_cap, OWNER);
    cleanup(scenario, other_vault, spend_cap, owner_cap, test_clock);
}

// Overflow guard: after spending 1 MIST, asking for u64::MAX must abort
// with OUR error code. The first spend matters: with spent = 0, the old
// check (spent + amount) would not overflow, and this test couldn't fail.
#[test, expected_failure(abort_code = vault::ELimitExceeded)]
fun huge_amount_fails_with_limit_error() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();

    let first = vault.spend(&spend_cap, 1, &test_clock, scenario.ctx());
    transfer::public_transfer(first, AGENT);

    //u64::MAX
    let second = vault.spend(
        &spend_cap,
        18_446_744_073_709_551_615,
        &test_clock,
        scenario.ctx(),
    );

    transfer::public_transfer(second, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Generics: the full flow (create, issue, deposit, spend) works for a
// coin type other than SUI.

#[test]
fun vault_works_with_non_sui_coin() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);

    let owner_cap = vault::create<TEST_USD>(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<TEST_USD>>();
    vault.deposit(coin::mint_for_testing<TEST_USD>(1000, scenario.ctx()));
    vault.issue_spend_cap(
        &owner_cap,
        AGENT,
        100,
        DAY_MS,
        START_MS + 7 * DAY_MS,
        &test_clock,
        scenario.ctx(),
    );
    test_scenario::return_shared(vault);

    scenario.next_tx(AGENT);
    let mut vault = scenario.take_shared<Vault<TEST_USD>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();

    let coin = vault.spend(&spend_cap, 100, &test_clock, scenario.ctx());
    assert!(coin.value() == 100);
    assert!(vault.balance_value() == 900);

    transfer::public_transfer(coin, AGENT);
    test_scenario::return_shared(vault);
    scenario.return_to_sender(spend_cap);
    transfer::public_transfer(owner_cap, OWNER);
    test_clock.destroy_for_testing();
    scenario.end();
}

// Security: an OwnerCap for vault B must not plant a spend cap on vault A.
#[test, expected_failure(abort_code = vault::ENotOwner)]
fun other_owner_cap_cannot_issue_on_vault() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);

    let cap_a = vault::create<SUI>(scenario.ctx());
    let cap_b = vault::create<SUI>(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault_a = scenario.take_shared_by_id<Vault<SUI>>(cap_a.vault_id());
    vault_a.issue_spend_cap(
        &cap_b,
        AGENT,
        ONE_SUI,
        DAY_MS,
        START_MS + 7 *DAY_MS,
        &test_clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(vault_a);
    transfer::public_transfer(cap_a, OWNER);
    transfer::public_transfer(cap_b, OWNER);
    test_clock.destroy_for_testing();
    scenario.end();
}

//Multiple caps: two caps on one vault keep separate totals.
#[test]
fun two_caps_track_spending_separately() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    //setup ended as AGENT; issuing is the owner's job.
    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    vault.issue_spend_cap(
        &owner_cap,
        AGENT_2,
        ONE_SUI,
        DAY_MS,
        START_MS + 7 * DAY_MS,
        &test_clock,
        scenario.ctx(),
    );
    test_scenario::return_shared(vault);

    // AGENT spends its full limit.
    scenario.next_tx(AGENT);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    let cap_1 = scenario.take_from_sender<SpendCap>();
    let cap_1_id = object::id(&cap_1);
    let c1 = vault.spend(&cap_1, ONE_SUI, &test_clock, scenario.ctx());
    transfer::public_transfer(c1, AGENT);
    test_scenario::return_shared(vault);
    scenario.return_to_sender(cap_1);

    // AGENT_2 can still spend its full limit in the same period.
    scenario.next_tx(AGENT_2);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    let cap_2 = scenario.take_from_sender<SpendCap>();
    let c2 = vault.spend(&cap_2, ONE_SUI, &test_clock, scenario.ctx());
    assert!(c2.value() == ONE_SUI);
    assert!(vault.spent_in_period(cap_1_id) == ONE_SUI);
    assert!(vault.spent_in_period(object::id(&cap_2)) == ONE_SUI);
    assert!(vault.balance_value() == 8 * ONE_SUI);

    transfer::public_transfer(c2, AGENT_2);
    cleanup(scenario, vault, cap_2, owner_cap, test_clock);
}

// Revocation: after owner revokes, the agent's next spend aborts,
// even though the agent still holds the SpendCap object.
#[test, expected_failure(abort_code = vault::ECapRevoked)]
fun revoked_cap_cannot_spend() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    revoke_as_owner(&mut scenario, &owner_cap, cap_id_of(AGENT));

    scenario.next_tx(AGENT);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    let coin = vault.spend(&spend_cap, 1, &test_clock, scenario.ctx());

    transfer::public_transfer(coin, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Revoking an already-revoked cap aborts with our code, not a framework one.
#[test, expected_failure(abort_code = vault::ECapRevoked)]
fun cannot_revoke_twice() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    let cap_id = cap_id_of(AGENT);
    revoke_as_owner(&mut scenario, &owner_cap, cap_id);
    revoke_as_owner(&mut scenario, &owner_cap, cap_id);

    scenario.next_tx(AGENT);
    let vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Security: vault B's OwnerCap must not revoke vault A's caps.
#[test, expected_failure(abort_code = vault::ENotOwner)]
fun other_owner_cap_cannot_revoke() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    scenario.next_tx(OWNER);
    let mut cap_b = vault::create<SUI>(scenario.ctx());

    // Two SUI vaults exist now, so take A by ID
    scenario.next_tx(OWNER);
    let mut vault_a = scenario.take_shared_by_id<Vault<SUI>>(owner_cap.vault_id());
    vault_a.revoke_spend_cap(&cap_b, cap_id_of(AGENT));

    test_scenario::return_shared(vault_a);
    transfer::public_transfer(cap_b, OWNER);
    transfer::public_transfer(owner_cap, OWNER);
    test_clock.destroy_for_testing();
    scenario.end();
}

// Revoke one cap removes only its own rules; other caps keep working.
#[test]
fun revoking_one_cap_leaves_others_active() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    vault.issue_spend_cap(
        &owner_cap,
        AGENT_2,
        ONE_SUI,
        DAY_MS,
        START_MS + 7 * DAY_MS,
        &test_clock,
        scenario.ctx(),
    );
    test_scenario::return_shared(vault);

    let cap_1_id = cap_id_of(AGENT);
    revoke_as_owner(&mut scenario, &owner_cap, cap_1_id);

    scenario.next_tx(AGENT_2);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    let cap_2 = scenario.take_from_sender<SpendCap>();
    assert!(!vault.is_active(cap_1_id));
    assert!(vault.is_active(object::id(&cap_2)));

    let coin = vault.spend(&cap_2, ONE_SUI, &test_clock, scenario.ctx());
    assert!(coin.value() == ONE_SUI);

    transfer::public_transfer(coin, AGENT_2);
    cleanup(scenario, vault, cap_2, owner_cap, test_clock);
}

// Allowlist, happy path: a restricted cap pays a listed recipient, and
// the coin lands at the recipient, not at the agent.
#[test]
fun restricted_cap_pays_allowed_recipient() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);
    set_allowlist_as_owner(&mut scenario, &owner_cap, cap_id_of(AGENT), vector[RECIPIENT]);

    scenario.next_tx(AGENT);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    let cap_id = object::id(&spend_cap);
    assert!(vault.is_recipient_allowed(cap_id, RECIPIENT));
    assert!(!vault.is_recipient_allowed(cap_id, OTHER));

    vault.spend_to(&spend_cap, ONE_SUI / 2, RECIPIENT, &test_clock, scenario.ctx());
    assert!(vault.spent_in_period(cap_id) == ONE_SUI / 2);
    test_scenario::return_shared(vault);
    scenario.return_to_sender(spend_cap);

    scenario.next_tx(RECIPIENT);
    let paid = scenario.take_from_sender<Coin<SUI>>();
    assert!(paid.value() == ONE_SUI / 2);
    scenario.return_to_sender(paid);

    transfer::public_transfer(owner_cap, OWNER);
    test_clock.destroy_for_testing();
    scenario.end();
}

// Allowlist: an unlisted recipient is refused.
#[test, expected_failure(abort_code = vault::ERecipientNotAllowed)]
fun restricted_cap_rejects_other_recipient() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);
    set_allowlist_as_owner(&mut scenario, &owner_cap, cap_id_of(AGENT), vector[RECIPIENT]);

    scenario.next_tx(AGENT);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    vault.spend_to(&spend_cap, 1, OTHER, &test_clock, scenario.ctx());

    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Allowlist: a restricted cap cannot use `spend`, because the returned
// coin could be sent anywhere.
#[test, expected_failure(abort_code = vault::ERestrictedCap)]
fun restricted_cap_cannot_use_spend() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);
    set_allowlist_as_owner(&mut scenario, &owner_cap, cap_id_of(AGENT), vector[RECIPIENT]);

    scenario.next_tx(AGENT);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    let coin = vault.spend(&spend_cap, 1, &test_clock, scenario.ctx());

    transfer::public_transfer(coin, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Allowlist: an empty list is rejected; "pay nobody" is what revoke is for.
#[test, expected_failure(abort_code = vault::EEmptyAllowlist)]
fun empty_allowlist_is_rejected() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);
    set_allowlist_as_owner(&mut scenario, &owner_cap, cap_id_of(AGENT), vector[]);

    scenario.next_tx(AGENT);
    let vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Allowlist: clearing it makes the cap unrestricted again, so `spend` works.
#[test]
fun clear_allowlist_lifts_restriction() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);
    let cap_id = cap_id_of(AGENT);
    set_allowlist_as_owner(&mut scenario, &owner_cap, cap_id, vector[RECIPIENT]);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    vault.clear_allowlist(&owner_cap, cap_id);
    test_scenario::return_shared(vault);

    scenario.next_tx(AGENT);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    assert!(vault.is_recipient_allowed(cap_id, OTHER));
    let coin = vault.spend(&spend_cap, 1, &test_clock, scenario.ctx());
    assert!(coin.value() == 1);

    transfer::public_transfer(coin, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Security: vault B's OwnerCap must not set vault A's allowlists.
#[test, expected_failure(abort_code = vault::ENotOwner)]
fun other_owner_cap_cannot_set_allowlist() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);

    scenario.next_tx(OWNER);
    let cap_b = vault::create<SUI>(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault_a = scenario.take_shared_by_id<Vault<SUI>>(owner_cap.vault_id());
    vault_a.set_allowlist(&cap_b, cap_id_of(AGENT), vector[OTHER]);

    test_scenario::return_shared(vault_a);
    transfer::public_transfer(cap_b, OWNER);
    transfer::public_transfer(owner_cap, OWNER);
    test_clock.destroy_for_testing();
    scenario.end();
}

// Events: the owner learns a new cap's ID from SpendCapIssued, the way a
// real revoke script would, and it matches the object the agent received.
#[test]
fun owner_learns_cap_id_from_issue_event() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = vault::create<SUI>(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    vault.issue_spend_cap(
        &owner_cap,
        AGENT,
        ONE_SUI,
        DAY_MS,
        START_MS + 7 * DAY_MS,
        &test_clock,
        scenario.ctx(),
    );
    let issued = event::events_by_type<SpendCapIssued<SUI>>();
    assert!(issued.length() == 1);
    let cap_id = vault::issued_cap_id(&issued[0]);
    test_scenario::return_shared(vault);

    scenario.next_tx(AGENT);
    let spend_cap = scenario.take_from_sender<SpendCap>();
    assert!(object::id(&spend_cap) == cap_id);

    scenario.return_to_sender(spend_cap);
    transfer::public_transfer(owner_cap, OWNER);
    test_clock.destroy_for_testing();
    scenario.end();
}

// Events: Spent records exact amount, recipient and running total.
// spend_to names the recipient; spend reports none (coin went to the PTB).
#[test]
fun spend_events_record_amount_and_recipient() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = setup(&mut scenario, &test_clock);
    let vault_id = owner_cap.vault_id();

    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    let cap_id = object::id(&spend_cap);

    // spend_to on an UNRESTRICTED cap: allowed, and the event names the recipient.
    vault.spend_to(&spend_cap, ONE_SUI / 2, RECIPIENT, &test_clock, scenario.ctx());
    assert!(
        event::events_by_type<Spent<SUI>>() == vector[
            vault::new_spent_for_testing<SUI>(
                vault_id,
                cap_id,
                ONE_SUI / 2,
                option::some(RECIPIENT),
                ONE_SUI / 2,
            ),
        ],
    );
    test_scenario::return_shared(vault);
    scenario.return_to_sender(spend_cap);

    scenario.next_tx(AGENT);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    let spend_cap = scenario.take_from_sender<SpendCap>();
    let coin = vault.spend(&spend_cap, ONE_SUI / 4, &test_clock, scenario.ctx());
    assert!(
        event::events_by_type<Spent<SUI>>() == vector[
            vault::new_spent_for_testing<SUI>(
                vault_id,
                cap_id,
                ONE_SUI / 4,
                option::none(),
                3 * ONE_SUI / 4,
            ),
        ],
    );

    transfer::public_transfer(coin, AGENT);
    cleanup(scenario, vault, spend_cap, owner_cap, test_clock);
}

// Events: each admin action emits exactly one event of its own type,
// and nothing emits twice.
#[test]
fun admin_actions_emit_one_event_each() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut test_clock = clock::create_for_testing(scenario.ctx());
    test_clock.set_for_testing(START_MS);
    let owner_cap = vault::create<SUI>(scenario.ctx());
    assert!(event::events_by_type<VaultCreated<SUI>>().length() == 1);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_shared<Vault<SUI>>();
    vault.deposit(coin::mint_for_testing<SUI>(ONE_SUI, scenario.ctx()));
    let coin = vault.withdraw(&owner_cap, ONE_SUI / 2, scenario.ctx());
    transfer::public_transfer(coin, OWNER);
    vault.issue_spend_cap(
        &owner_cap,
        AGENT,
        ONE_SUI,
        DAY_MS,
        START_MS + 7 * DAY_MS,
        &test_clock,
        scenario.ctx(),
    );
    let issued = event::events_by_type<SpendCapIssued<SUI>>();
    let cap_id = vault::issued_cap_id(&issued[0]);
    vault.set_allowlist(&owner_cap, cap_id, vector[RECIPIENT]);
    vault.clear_allowlist(&owner_cap, cap_id);
    vault.revoke_spend_cap(&owner_cap, cap_id);

    assert!(event::events_by_type<Deposited<SUI>>().length() == 1);
    assert!(event::events_by_type<Withdrawn<SUI>>().length() == 1);
    assert!(event::events_by_type<SpendCapIssued<SUI>>().length() == 1);
    assert!(event::events_by_type<AllowlistSet>().length() == 1);
    assert!(event::events_by_type<AllowlistCleared>().length() == 1);
    assert!(event::events_by_type<SpendCapRevoked>().length() == 1);
    assert!(event::num_events() == 6);

    test_scenario::return_shared(vault);
    transfer::public_transfer(owner_cap, OWNER);
    test_clock.destroy_for_testing();
    scenario.end();
}
