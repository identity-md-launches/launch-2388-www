# WWW token tests

The suite tests the deployed `WWWToken` through its public interface. The expected
supply is independently fixed at `1_000_000_000 * 10 ** 18`; tests do not derive it
from the contract's supply getter. Existing constructor, metadata, event, factory
distribution and privilege checks remain in `WWWToken.t.sol`.

`WWWToken.edge.t.sol` adds explicit zero, one-wei, full-supply, `uint256.max - 1`
and `uint256.max` cases. It checks that failed transfers preserve state, that
self-transfers cannot bypass balances or approvals, and that refilling a holder
does not renew an exhausted allowance. Infinite approvals remain usable after
refilling, but replacing them with a finite amount restricts subsequent spending.
Six additional fuzz properties check transfer round trips, split versus combined
transfers, approval replacement and isolation, full-range finite allowances, and
rollback on delegated overdraws or invalid receivers.

`WWWToken.invariant.t.sol` uses four actors and a closed set of token recipients.
Ghost balances and allowances are updated from intended operations, without
copying the token's resulting storage into the model. Ten handler actions mix
direct and delegated transfers, full-balance transfers, approvals, revocations,
and expected failures. After every action the invariant runner checks:

- Every actor's balance equals its model balance; all balances sum to the fixed
  supply. The deployer, token contract and zero address retain no tokens.
- All sixteen actor-to-actor allowances equal their last approval less successful
  finite spending. Rejected transactions consume no allowance. Neither the zero
  address nor the deploying handler gains approval.
- The name, symbol and decimals remain `www`, `WWW` and `18`.

A deterministic handler test also exercises nonzero delegated spending, finite
and infinite approvals, revocation, each expected failure and full-balance moves.
Unexpected handler reverts fail the campaign. Inline settings run each fuzz
property 1,024 times and the invariant campaign for 256 sequences of 128 calls.

Run from the repository root:

```sh
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache forge build
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache FOUNDRY_FUZZ_SEED=0x0fcd0c10eafab6b69601c0238a6e8364b5557c2137afbe85dfe3816a93530fe5 forge test
```

The output/cache overrides only keep generated files inside scratch. Tests use
the existing vendored dependencies and require no network, fork, external
addresses or environment reads. The factory fixture tests token-side custody
flows; the supplied protected Uniswap/factory integration checks require the
separate launch infrastructure and are not reproduced by that fixture.
