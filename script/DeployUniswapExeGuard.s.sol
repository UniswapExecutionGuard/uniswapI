// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";
import {HookDeployer} from "./HookDeployer.sol";
import {HookAddressLib} from "./HookAddressLib.sol";

contract DeployUniswapExeGuard is Script {
    uint256 private constant MAX_SALT_SEARCH = 500_000;

    error HookSaltNotFound();
    error HookAddressMismatch(address expected, address actual);
    error HookOwnerMismatch(address expected, address actual);

    function run() external returns (PolicyRegistry registry, UniswapExeGuard hook) {
        address ensRegistry = vm.envAddress("ENS_REGISTRY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address owner = vm.envOr("OWNER", address(0));
        uint256 defaultMaxSwapAbs = vm.envOr("DEFAULT_MAX_SWAP_ABS", uint256(1 ether));
        uint256 defaultCooldownSeconds = vm.envOr("DEFAULT_COOLDOWN_SECONDS", uint256(60));

        require(ensRegistry != address(0), "ENS_REGISTRY is zero");
        require(poolManager != address(0), "POOL_MANAGER is zero");
        require(owner != address(0), "OWNER is zero");

        vm.startBroadcast();
        registry = new PolicyRegistry(ensRegistry);

        HookDeployer deployer = new HookDeployer();
        bytes memory hookCreationCode = abi.encodePacked(
            type(UniswapExeGuard).creationCode,
            abi.encode(poolManager, address(registry), defaultMaxSwapAbs, defaultCooldownSeconds)
        );
        bytes32 initCodeHash = keccak256(hookCreationCode);

        (bytes32 salt, address predictedHookAddress, bool found) =
            HookAddressLib.findBeforeSwapSalt(address(deployer), initCodeHash, MAX_SALT_SEARCH);
        if (!found) revert HookSaltNotFound();
        address deployedHookAddress = deployer.deployAndTransferOwnership(salt, hookCreationCode, owner);
        if (deployedHookAddress != predictedHookAddress) {
            revert HookAddressMismatch(predictedHookAddress, deployedHookAddress);
        }

        hook = UniswapExeGuard(deployedHookAddress);
        if (hook.owner() != owner) {
            revert HookOwnerMismatch(owner, hook.owner());
        }
        hook.validateHookAddress();
        vm.stopBroadcast();

        console2.log("PolicyRegistry:", address(registry));
        console2.log("HookDeployer:", address(deployer));
        console2.log("UniswapExeGuard:", address(hook));
        console2.log("Owner:", owner);
        console2.log("salt:");
        console2.logBytes32(salt);
        console2.log("defaultMaxSwapAbs:", defaultMaxSwapAbs);
        console2.log("defaultCooldownSeconds:", defaultCooldownSeconds);
    }
}
