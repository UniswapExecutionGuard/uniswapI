// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "./BaseHook.sol";
import {PolicyRegistry} from "./PolicyRegistry.sol";
import {Ownable} from "../lib/v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IHooks} from "../lib/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../lib/v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../lib/v4-core/src/types/BeforeSwapDelta.sol";
import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";
import {IMsgSender} from "../lib/v4-periphery/src/interfaces/IMsgSender.sol";

contract UniswapExeGuard is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;

    PolicyRegistry public immutable registry;

    // Default values when trader-specific policies are absent in PolicyRegistry.
    // Initialized in constructor and updatable by owner via setDefaults.
    uint256 public defaultMaxSwapAbs;
    uint256 public defaultCooldownSeconds;

    mapping(address => bool) public trustedMsgSenderProviders;
    // Cooldown is enforced per trader per pool (not globally across all pools).
    mapping(address => mapping(bytes32 => uint256)) public lastSwapTimestampByPool;

    error AmountSpecifiedInvalid();
    error MaxSwapExceeded(uint256 maxAllowed, uint256 attempted);
    error CooldownNotElapsed(uint256 nextAllowedTime, uint256 currentTime);
    error PolicyRegistryZero();
    error ProviderZeroAddress();

    event SwapAllowed(address indexed trader, int256 amountSpecified, uint256 maxSwapAbs, uint256 cooldownSeconds);
    event SwapBlocked(address indexed trader, uint8 reason, int256 amountSpecified);
    event DefaultsUpdated(uint256 defaultMaxSwapAbs, uint256 defaultCooldownSeconds);
    event TrustedMsgSenderProviderUpdated(address indexed provider, bool trusted);

    //using constants for readability and gas efficiency in event logs
    uint8 private constant REASON_MAX_SWAP = 1;
    uint8 private constant REASON_COOLDOWN = 2;
    uint8 private constant REASON_INVALID_AMOUNT = 3;

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions = Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Validates that this deployed address encodes the required hook permission bits.
    /// Reverts with `Hooks.HookAddressNotValid` when deployed at an invalid address.
    function validateHookAddress() external view {
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    constructor(
        address poolManager,
        address policyRegistry,
        uint256 _defaultMaxSwapAbs,
        uint256 _defaultCooldownSeconds
    ) BaseHook(poolManager) Ownable(msg.sender) {
        require(policyRegistry != address(0), PolicyRegistryZero());
        registry = PolicyRegistry(policyRegistry);
        defaultMaxSwapAbs = _defaultMaxSwapAbs;
        defaultCooldownSeconds = _defaultCooldownSeconds;
    }

    function setDefaults(uint256 _defaultMaxSwapAbs, uint256 _defaultCooldownSeconds) external onlyOwner {
        defaultMaxSwapAbs = _defaultMaxSwapAbs;
        defaultCooldownSeconds = _defaultCooldownSeconds;
        emit DefaultsUpdated(_defaultMaxSwapAbs, _defaultCooldownSeconds);
    }

    /// @notice Marks a router/periphery contract as trusted to expose end user via IMsgSender.msgSender().
    function setTrustedMsgSenderProvider(address provider, bool trusted) external onlyOwner {
        require(provider != address(0), ProviderZeroAddress());
        trustedMsgSenderProviders[provider] = trusted;
        emit TrustedMsgSenderProviderUpdated(provider, trusted);
    }

    function beforeSwap(address trader, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        address policyTrader = _resolvePolicyTrader(trader);
        PoolKey memory keyForId = key;
        bytes32 poolId = PoolId.unwrap(keyForId.toId());
        int256 amountSpecified = params.amountSpecified;
        if (amountSpecified == type(int256).min) {
            emit SwapBlocked(policyTrader, REASON_INVALID_AMOUNT, amountSpecified);
            revert AmountSpecifiedInvalid();
        }

        // Safe cast: int256.min is rejected above; remaining values convert to uint256 safely.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 absAmount = amountSpecified < 0 ? uint256(-amountSpecified) : uint256(amountSpecified);
        (uint256 maxSwapAbs, uint256 cooldownSeconds) = _policyFor(policyTrader);

        if (maxSwapAbs > 0 && absAmount > maxSwapAbs) {
            emit SwapBlocked(policyTrader, REASON_MAX_SWAP, amountSpecified);
            revert MaxSwapExceeded(maxSwapAbs, absAmount);
        }

        uint256 last = lastSwapTimestampByPool[policyTrader][poolId];
        if (cooldownSeconds > 0 && last != 0 && block.timestamp < last + cooldownSeconds) {
            emit SwapBlocked(policyTrader, REASON_COOLDOWN, amountSpecified);
            revert CooldownNotElapsed(last + cooldownSeconds, block.timestamp);
        }

        lastSwapTimestampByPool[policyTrader][poolId] = block.timestamp;
        emit SwapAllowed(policyTrader, amountSpecified, maxSwapAbs, cooldownSeconds);
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _policyFor(address trader) internal view returns (uint256 maxSwapAbs, uint256 cooldownSeconds) {
        bool hasCustomPolicy;
        (maxSwapAbs, cooldownSeconds, hasCustomPolicy) = registry.getPolicy(trader);
        // No custom policy for this trader: enforce defaults.
        if (!hasCustomPolicy) {
            return (defaultMaxSwapAbs, defaultCooldownSeconds);
        }
    }

    function _resolvePolicyTrader(address sender) internal view returns (address) {
        if (!trustedMsgSenderProviders[sender]) return sender;
        try IMsgSender(sender).msgSender() returns (address originalSender) {
            return originalSender == address(0) ? sender : originalSender;
        } catch {
            return sender;
        }
    }
}
