// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "./BaseHook.sol";
import {PolicyRegistry} from "./PolicyRegistry.sol";
import {Ownable} from "../lib/v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IHooks} from "../lib/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../lib/v4-core/src/types/BeforeSwapDelta.sol";
import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";

contract UniswapExeGuard is BaseHook, Ownable {
    PolicyRegistry public immutable registry;

    // Default values when trader-specific policies are absent in PolicyRegistry.
    // Initialized in constructor and updatable by owner via setDefaults.
    uint256 public defaultMaxSwapAbs;
    uint256 public defaultCooldownSeconds;

    mapping(address => uint256) public lastSwapTimestamp;

    error AmountSpecifiedInvalid();
    error MaxSwapExceeded(uint256 maxAllowed, uint256 attempted);
    error CooldownNotElapsed(uint256 nextAllowedTime, uint256 currentTime);
    error PolicyRegistryZero();

    event SwapAllowed(address indexed trader, int256 amountSpecified, uint256 maxSwapAbs, uint256 cooldownSeconds);
    event SwapBlocked(address indexed trader, uint8 reason, int256 amountSpecified);
    event DefaultsUpdated(uint256 defaultMaxSwapAbs, uint256 defaultCooldownSeconds);

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

    function beforeSwap(address trader, PoolKey calldata, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        int256 amountSpecified = params.amountSpecified;
        if (amountSpecified == type(int256).min) {
            emit SwapBlocked(trader, REASON_INVALID_AMOUNT, amountSpecified);
            revert AmountSpecifiedInvalid();
        }

        uint256 absAmount = amountSpecified < 0 ? uint256(-amountSpecified) : uint256(amountSpecified);
        (uint256 maxSwapAbs, uint256 cooldownSeconds) = _policyFor(trader);

        if (maxSwapAbs > 0 && absAmount > maxSwapAbs) {
            emit SwapBlocked(trader, REASON_MAX_SWAP, amountSpecified);
            revert MaxSwapExceeded(maxSwapAbs, absAmount);
        }

        uint256 last = lastSwapTimestamp[trader];
        if (cooldownSeconds > 0 && last != 0 && block.timestamp < last + cooldownSeconds) {
            emit SwapBlocked(trader, REASON_COOLDOWN, amountSpecified);
            revert CooldownNotElapsed(last + cooldownSeconds, block.timestamp);
        }

        lastSwapTimestamp[trader] = block.timestamp;
        emit SwapAllowed(trader, amountSpecified, maxSwapAbs, cooldownSeconds);
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
}
