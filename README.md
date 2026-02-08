# UniswapExeGuard

UniswapExeGuard demonstrates how Uniswap v4 hooks can be used to embed execution rules directly into a liquidity pool's swap lifecycle. It implements a `beforeSwap` hook that enforces deterministic, pool-level execution policies (e.g. trade size limits and cooldowns), enabling new market structures that are not possible in earlier Uniswap versions.

## Upstream Dependencies

- ENS contracts: `https://github.com/ensdomains/ens-contracts`
- Uniswap v4 core: `https://github.com/Uniswap/v4-core`
- Uniswap v4 periphery: `https://github.com/Uniswap/v4-periphery`

This repo consumes those packages from `lib/` and uses official interfaces/types in the contracts.

## What It Does

- Enforces maximum trade size per trader at swap execution time (`maxSwapAbs`)
- Rate-limits order flow via mandatory cooldowns between swaps (`cooldownSeconds`) per trader per pool
- Uses ENS to map human-readable names to addresses at setup time
- Applies safe defaults for traders without policies

## Contracts

- `src/PolicyRegistry.sol`
  - Stores per-address policies
  - Resolves ENS names to addresses at setup time
  - Exposes `getPolicy(address)` for hooks

- `src/UniswapExeGuard.sol`
  - Uniswap v4 hook that enforces policies in `beforeSwap`
  - Execution rules are enforced as part of the pool's swap lifecycle
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

Set values in `.env`:

```shell
SEPOLIA_RPC_URL=<your_sepolia_rpc_url>
ENS_REGISTRY=<ens_registry_address>
POOL_MANAGER=<uniswap_v4_pool_manager_address>
DEFAULT_MAX_SWAP_ABS=<optional_uint>
DEFAULT_COOLDOWN_SECONDS=<optional_uint>
```

Important Uniswap v4 hook deployment constraint:

- Hook behavior is selected by permission bits encoded in the hook contract address.
- This guard enables `beforeSwap`, so the deployed hook address must include the `BEFORE_SWAP` flag bits.
- `validateHookAddress()` reverts if the current deployment address does not match declared permissions.
- `script/DeployUniswapExeGuard.s.sol` handles this automatically by:
  - deploying a small CREATE2 factory
  - mining a salt whose predicted hook address has the correct `beforeSwap` flag bits
  - deploying the hook with CREATE2 and validating via `validateHookAddress()`

### Sepolia Account-Based Deploy (Interactive Wallet)

Import a deployer account once:

```shell
make sepolia-import ACCOUNT=sepolia-deployer
```

Create a `.password` file (same password used for the imported cast wallet), then deploy:

```shell
make sepolia-deploy
```

This uses:

- `SEPOLIA_RPC_URL` from `.env`
- `ENS_REGISTRY` and `POOL_MANAGER` from `.env`
- `ACCOUNT` and `PASSWORD_FILE` from `Makefile` defaults (override if needed)
- `OWNER` is derived automatically from `ACCOUNT` during `make sepolia-deploy` so hook admin calls work after CREATE2 deployment

### Sepolia Demo Scripts

Optional `.env` values for demo interaction scripts:

```shell
POLICY_REGISTRY=<deployed_policy_registry_address>
UNISWAP_EXE_GUARD=<deployed_hook_address>
TRADER=<trader_address_for_demo>
ENS_NAME=<ens_name_for_demo>
```

Available commands:

```shell
make sepolia-policy-set
make sepolia-policy-set-ens
make sepolia-policy-read
make sepolia-hook-config
make sepolia-demo-sequence
make sepolia-live-swap
```

`make sepolia-live-swap` runs a real Uniswap v4 flow against Sepolia `POOL_MANAGER`:

- deploys 2 test ERC20s
- initializes a hook-enabled pool
- adds liquidity
- executes one allowed swap and one blocked swap

Optional `.env` overrides for this command:

```shell
LIVE_TOKEN_MINT=<default 1000000 ether>
LIVE_LIQUIDITY_DELTA=<default 1000000>
LIVE_ALLOWED_INPUT=<default 0.1 ether>
LIVE_BLOCKED_INPUT=<default 2 ether>
LIVE_MAX_SWAP_ABS=<default 1 ether>
LIVE_COOLDOWN_SECONDS=<default 0>
LIVE_POOL_FEE=<default 3000>
LIVE_TICK_SPACING=<default 60>
LIVE_TICK_LOWER=<default -120>
LIVE_TICK_UPPER=<default 120>
```

## Demo (Local TxIDs)

Set Anvil key in `.env`:

```shell
PRIVATE_KEY_ANVIL=<anvil_private_key>
```

Run Anvil in one terminal:

```shell
make local-node
```

In another terminal:

```shell
make local-demo
```

This produces broadcast transactions for:

- Deployment/setup
- Allowed swap attempt
- Blocked swap attempt (policy violation)

The demo script deploys the hook via CREATE2 with mined salt, so `beforeSwap` permission bits are valid there as well.

Check the printed transaction hashes and `SwapExecutor.SwapAttempt` event results in the broadcast output.

## Demo UI

Run:

```shell
make ui-demo
```

Then open `http://127.0.0.1:4173`.

For GitHub Pages deployment (serving from `docs/`), sync the latest UI first:

```shell
make ui-pages
git add docs Makefile README.md
git commit -m "chore: sync demo-ui to docs for GitHub Pages"
git push
```

Pages URL format:

`https://<github-username>.github.io/<repo-name>/`

UI features:

- Connect wallet (MetaMask/Rabby)
- Set/read/clear policies in `PolicyRegistry` (address or ENS)
- Set ENS-based policy
- Set hook defaults
- Run live swap checks via `PoolSwapTest` (approve tokens, allowed swap, blocked swap)
- View recent `PolicySet`, `PolicyCleared`, `DefaultsUpdated`, `SwapAllowed`, and `SwapBlocked` events
- Auto-prefill contract addresses and default values from `.env` via generated `demo-ui/config.js` and `docs/config.js`

## Demo Flow (Expected)

- Configure policy for `alice.eth` via `PolicyRegistry.setPolicyForENS`
- Swap via the pool manager and observe (policy is evaluated for the swap caller/sender):
  - Allowed swap emits `SwapAllowed` audit events
  - Policy violations emit `SwapBlocked` audit events with reason
  - Violations revert with `MaxSwapExceeded` or `CooldownNotElapsed`

## Notes

- ENS resolution happens only at policy setup time
- No UI dependencies; deterministic behavior
- Execution rules are enforced by the Uniswap v4 PoolManager, not by off-chain logic (main point!)
