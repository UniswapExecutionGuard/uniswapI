// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract BaseHook {
    address public immutable poolManager;

    constructor(address _poolManager) {
        require(_poolManager != address(0), "PM_ZERO");
        poolManager = _poolManager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == poolManager, "NOT_POOL_MANAGER");
        _;
    }
}
