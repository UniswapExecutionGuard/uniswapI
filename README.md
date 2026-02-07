# UniswapExeGuard

UniswapExeGuard is a policy enforcement layer for Uniswap v4-style execution. It uses an on-chain hook (`beforeSwap`) to enforce per-trader execution rules, with policies configured via ENS names.

## Upstream Dependencies

- ENS contracts: `https://github.com/ensdomains/ens-contracts`
- Uniswap v4 core: `https://github.com/Uniswap/v4-core`
- Uniswap v4 periphery: `https://github.com/Uniswap/v4-periphery`

This repo consumes those packages from `lib/` and uses official interfaces/types in the contracts.

## What It Does

- Enforces max trade size per trader (`maxSwapAbs`)
- Enforces cooldowns between swaps (`cooldownSeconds`)
- Uses ENS to map human-readable names to addresses at setup time
- Applies safe defaults for traders without policies

## Contracts

- `src/PolicyRegistry.sol`
  - Stores per-address policies
  - Resolves ENS names to addresses at setup time
  - Exposes `getPolicy(address)` for hooks

- `src/UniswapExeGuard.sol`
  - Hook that enforces policies in `beforeSwap`
  - Emits audit events for allowed/blocked swaps
  - Applies global defaults if no policy exists
  - Declares `Hooks.Permissions` and includes `validateHookAddress()`

- `src/ENS.sol`
  - ENS interfaces + namehash helper

## Tests

Tests are in `test/UniswapExeGuard.t.sol` and include:

- ENS name resolution and policy storage
- Allowed swap within limits
- Reverts on max swap violation
- Reverts on cooldown violation
- Defaults applied for missing policies

## Build

```shell
forge build
```

## Test

```shell
forge test
```

## Deploy (Testnet)

Set environment variables:

```shell
export PRIVATE_KEY=<deployer_private_key>
export ENS_REGISTRY=<ens_registry_address>
export POOL_MANAGER=<uniswap_v4_pool_manager_address>
export DEFAULT_MAX_SWAP_ABS=<optional_uint>
export DEFAULT_COOLDOWN_SECONDS=<optional_uint>
```

Important Uniswap v4 hook deployment constraint:

- Hook behavior is selected by permission bits encoded in the hook contract address.
- This guard enables `beforeSwap`, so the deployed hook address must include the `BEFORE_SWAP` flag bits.
- `validateHookAddress()` reverts if the current deployment address does not match declared permissions.

Run:

```shell
make deploy RPC_URL=<your_rpc_url>
```

## Demo (Local TxIDs)

Run Anvil in one terminal:

```shell
make demo-anvil
```

In another terminal:

```shell
export PRIVATE_KEY=<anvil_private_key>

make demo RPC_URL=http://127.0.0.1:8545
```

This produces broadcast transactions for:

- Deployment/setup
- Allowed swap attempt
- Blocked swap attempt (policy violation)

Check the printed transaction hashes and `SwapExecutor.SwapAttempt` event results in the broadcast output.

## Demo Flow (Expected)

- Configure policy for `alice.eth` via `PolicyRegistry.setPolicyForENS`
- Swap via the pool manager and observe (policy is evaluated for the swap caller/sender):
  - Allowed swap emits `SwapAllowed`
  - Violations revert with `MaxSwapExceeded` or `CooldownNotElapsed`

## Notes

- ENS resolution happens only at policy setup time
- No UI dependencies; deterministic behavior
