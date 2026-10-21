# www (WWW)

**Stop window shopping. See everything first.**  
X: [@windowshoppermd](https://x.com/windowshoppermd)

`src/WWWToken.sol` implements a fixed-supply ERC-20 using the vendored OpenZeppelin Contracts v5.0.2 implementation.

## Token specification and assumptions

| Parameter | Value |
| --- | --- |
| Solidity contract | `WWWToken` |
| Token name | `www` |
| Token symbol | `WWW` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer, `msg.sender` |
| Application contracts | None |

The tagline and X handle are branding. No shopping, access-control, website, or off-chain service behavior was specified. The contract implements standard ERC-20 transfers and approvals.

The constructor mints the entire supply once and emits one `Transfer` event from the zero address to the deployer. There is no callable mint, burn, owner, pause, blacklist, seizure, fee, rebase, initializer, or upgrade mechanism. No external contracts are called, either during construction or transfers. The deployed token's supply stays fixed.

Transfers deliver exactly the requested amount. Zero-amount transfers between valid addresses and self-transfers are supported. Transfers to the zero address, approvals to the zero address, insufficient balances, and insufficient allowances revert using OpenZeppelin's ERC-6093 custom errors. Failed transactions preserve balances and allowances.

`approve` replaces the existing allowance. Finite allowances decrease on successful `transferFrom`; an allowance of `type(uint256).max` remains unchanged. A zero-amount `transferFrom` between valid addresses needs no allowance. `Approval` is emitted for `approve`, and `Transfer` for transfers; this implementation does not emit an additional `Approval` event when `transferFrom` consumes allowance.

## Build and tests

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x0fcd0c10eafab6b69601c0238a6e8364b5557c2137afbe85dfe3816a93530fe5 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer enabled with 200 runs, and `bytecode_hash = "none"`. FFI and filesystem permissions are not enabled. All Solidity and testing dependencies are ordinary files in `lib/`; their pinned versions, archive hashes, and licenses are documented in `lib/README.md`. No package install, submodule, fork, RPC, environment value, or network access is required by the tests. The fuzz seed above is supplied by the assignment; it is not read by test code.

- Unit tests cover metadata, a single constructor mint, CREATE2 deployment, exact factory distribution and claims, transfers, events, finite/infinite approvals, approval replacement/revocation, self/zero transfers, and rejected native-currency deposits.
- Failure tests cover invalid recipients, insufficient balances/allowances, spending another account's allowance, approval reuse, transaction rollback, and attempts by both the deployer and an outsider to reach minting or privileged functions.
- Four fuzz properties run 1,024 cases each, checking transfer accounting, allowance consumption, and failure atomicity.
- Two stateful invariants run 128 sequences of 64 calls each. A handler mixes transfers, approvals, delegated transfers, and failed overspends across four actors. Independent balance and allowance models check conservation and authorization accounting after each call.

The factory fixture tests token-side custody flows only. It does not implement Uniswap or claim that a real pool swap was executed. The supplied protected launch tests depend on the network's separate factory/pool infrastructure and manifest parameters; those integration checks remain with the launch verifier.

## Deployment parameters

The launch target is Ethereum, chain ID **1**. Deploy the creation bytecode for `src/WWWToken.sol:WWWToken` with **no constructor arguments and no native-currency value**, using the exact build settings above. After `forge build`, the artifact is `out/WWWToken.sol/WWWToken.json`. The contract has no library link placeholders and requires no initialization transaction or pre-existing contract.

The account or contract executing CREATE/CREATE2 receives all `10^27` smallest units. In the intended launch this is the launch factory, which then distributes the supply. A direct deployment gives the entire supply to the direct deployer. An intermediate deployment helper would receive the tokens itself; it must be capable of forwarding them. No recipient or admin address is a token constructor parameter.

The following economics belong to the provided launch configuration, not to token transfer logic:

| Launch setting | Supplied value |
| --- | --- |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, 18 decimals |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Initial-price provenance | `79228162514264337593543950336` |
| Swarm share | 10% (`100,000,000 WWW`), distributed by the factory |
| `economics.poolBps` | `6000`: 60% (`600,000,000 WWW`) |
| `economics.initialMarketCapWei` | `888000000000000000000` (888 IMD) |
| `economics.remainderTo` | `0xee2aaa315cf7ed169f93148d30d24af9318dbb66` |
| Remainder | 30% (`300,000,000 WWW`) |

The launch deployer derives the actual opening pool price from the supplied market cap, supply, and token address. The token neither creates a pool nor enforces these allocations; the factory performs them after receiving the complete supply. The separate manifest step produces `launch.json` after acceptance. This project does not include a manifest or broadcast transactions.

## After launch

There are no owner-settable parameters, keepers, external services, or routine administration. The network's deployer is responsible for deploying through the intended factory, validating the deployed source/bytecode and metadata, performing the launch allocations and pool setup, and publishing the resulting token address. The requester is responsible for public branding and communications.

Holders control transfers and spender approvals. Approve only trusted spenders for the amounts needed; unlimited approvals let a spender use future balances as well. When replacing an existing nonzero allowance, first revoke it and confirm the revocation before granting a new amount to reduce the standard ERC-20 allowance-change race. An administrator cannot reverse confirmed transfers. There is no recovery function for WWW or unrelated tokens sent to the token contract, and ordinary native-currency deposits revert.

## Security review scope

The implementation was reviewed against the supplied security reference for decimal accounting, supply/privilege boundaries, allowance checks, rollback on failure, events, external calls, and upgrade/delegatecall exposure. The token has no callbacks, arbitrary external calls, signatures, oracle inputs, randomness, or custody application. OpenZeppelin's internal mint/burn helpers are not exposed through the deployed contract's ABI.

Local validation uses Foundry build, deterministic unit/fuzz tests, stateful invariants, and formatting checks. Slither and Mythril were not run. These checks are not an independent security audit; the network's independent adversarial review and launch integration checks remain release responsibilities.
