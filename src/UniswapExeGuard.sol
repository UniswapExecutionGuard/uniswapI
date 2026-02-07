// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "./BaseHook.sol";
import {PolicyRegistry} from "./PolicyRegistry.sol";
import {Ownable} from "./Ownable.sol";

contract UniswapExeGuard is BaseHook, Ownable {
    PolicyRegistry public immutable registry;

    uint256 public defaultMaxSwapAbs;
    uint256 public defaultCooldownSeconds;

    mapping(address => uint256) public lastSwapTimestamp;

    error AmountSpecifiedInvalid();
    error MaxSwapExceeded(uint256 maxAllowed, uint256 attempted);
    error CooldownNotElapsed(uint256 nextAllowedTime, uint256 currentTime);

    event SwapAllowed(address indexed trader, int256 amountSpecified, uint256 maxSwapAbs, uint256 cooldownSeconds);
    event SwapBlocked(address indexed trader, uint8 reason, int256 amountSpecified);
    event DefaultsUpdated(uint256 defaultMaxSwapAbs, uint256 defaultCooldownSeconds);

    uint8 private constant REASON_MAX_SWAP = 1;
    uint8 private constant REASON_COOLDOWN = 2;
    uint8 private constant REASON_INVALID_AMOUNT = 3;

    constructor(
        address poolManager,
        address policyRegistry,
        uint256 _defaultMaxSwapAbs,
        uint256 _defaultCooldownSeconds
    ) BaseHook(poolManager) {
        require(policyRegistry != address(0), "REG_ZERO");
        registry = PolicyRegistry(policyRegistry);
        defaultMaxSwapAbs = _defaultMaxSwapAbs;
        defaultCooldownSeconds = _defaultCooldownSeconds;
    }

    function setDefaults(uint256 _defaultMaxSwapAbs, uint256 _defaultCooldownSeconds) external onlyOwner {
        defaultMaxSwapAbs = _defaultMaxSwapAbs;
        defaultCooldownSeconds = _defaultCooldownSeconds;
        emit DefaultsUpdated(_defaultMaxSwapAbs, _defaultCooldownSeconds);
    }

    function beforeSwap(address trader, int256 amountSpecified) external onlyPoolManager {
        if (amountSpecified == type(int256).min) {
            emit SwapBlocked(trader, REASON_INVALID_AMOUNT, amountSpecified);
            revert AmountSpecifiedInvalid();
        }

        uint256 absAmount = amountSpecified < 0 ? uint256(-amountSpecified) : uint256(amountSpecified);

        (uint256 maxSwapAbs, uint256 cooldownSeconds, bool exists) = registry.getPolicy(trader);
        if (!exists) {
            maxSwapAbs = defaultMaxSwapAbs;
            cooldownSeconds = defaultCooldownSeconds;
        }

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
    }
}
