// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";

contract DeployUniswapExeGuard is Script {
    function run() external returns (PolicyRegistry registry, UniswapExeGuard hook) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ensRegistry = vm.envAddress("ENS_REGISTRY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        uint256 defaultMaxSwapAbs = vm.envOr("DEFAULT_MAX_SWAP_ABS", uint256(1 ether));
        uint256 defaultCooldownSeconds = vm.envOr("DEFAULT_COOLDOWN_SECONDS", uint256(60));

        require(ensRegistry != address(0), "ENS_REGISTRY is zero");
        require(poolManager != address(0), "POOL_MANAGER is zero");

        vm.startBroadcast(deployerKey);
        registry = new PolicyRegistry(ensRegistry);
        hook = new UniswapExeGuard(poolManager, address(registry), defaultMaxSwapAbs, defaultCooldownSeconds);
        vm.stopBroadcast();

        console2.log("PolicyRegistry:", address(registry));
        console2.log("UniswapExeGuard:", address(hook));
        console2.log("defaultMaxSwapAbs:", defaultMaxSwapAbs);
        console2.log("defaultCooldownSeconds:", defaultCooldownSeconds);
    }
}
