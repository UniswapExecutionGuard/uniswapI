// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";
import {HookDeployer} from "./HookDeployer.sol";

contract DeployUniswapExeGuard is Script {
    // Uniswap v4 encodes hook permissions in the low 14 bits of the hook contract address.
    uint160 private constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 private constant BEFORE_SWAP_FLAG = uint160(1 << 7);
    uint256 private constant MAX_SALT_SEARCH = 500_000;

    error HookSaltNotFound();
    error HookAddressMismatch(address expected, address actual);

    function run() external returns (PolicyRegistry registry, UniswapExeGuard hook) {
        address ensRegistry = vm.envAddress("ENS_REGISTRY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        uint256 defaultMaxSwapAbs = vm.envOr("DEFAULT_MAX_SWAP_ABS", uint256(1 ether));
        uint256 defaultCooldownSeconds = vm.envOr("DEFAULT_COOLDOWN_SECONDS", uint256(60));

        require(ensRegistry != address(0), "ENS_REGISTRY is zero");
        require(poolManager != address(0), "POOL_MANAGER is zero");

        vm.startBroadcast();
        registry = new PolicyRegistry(ensRegistry);

        HookDeployer deployer = new HookDeployer();
        bytes memory hookCreationCode = abi.encodePacked(
            type(UniswapExeGuard).creationCode,
            abi.encode(poolManager, address(registry), defaultMaxSwapAbs, defaultCooldownSeconds)
        );
        bytes32 initCodeHash = keccak256(hookCreationCode);

        (bytes32 salt, address predictedHookAddress) = _findSalt(address(deployer), initCodeHash);
        address deployedHookAddress = deployer.deploy(salt, hookCreationCode);
        if (deployedHookAddress != predictedHookAddress) {
            revert HookAddressMismatch(predictedHookAddress, deployedHookAddress);
        }

        hook = UniswapExeGuard(deployedHookAddress);
        hook.validateHookAddress();
        vm.stopBroadcast();

        console2.log("PolicyRegistry:", address(registry));
        console2.log("HookDeployer:", address(deployer));
        console2.log("UniswapExeGuard:", address(hook));
        console2.log("salt:");
        console2.logBytes32(salt);
        console2.log("defaultMaxSwapAbs:", defaultMaxSwapAbs);
        console2.log("defaultCooldownSeconds:", defaultCooldownSeconds);
    }

    function _findSalt(address deployer, bytes32 initCodeHash) internal pure returns (bytes32 salt, address hookAddr) {
        for (uint256 i = 0; i < MAX_SALT_SEARCH; i++) {
            salt = bytes32(i);
            hookAddr = _computeCreate2Address(deployer, salt, initCodeHash);
            if ((uint160(hookAddr) & ALL_HOOK_MASK) == BEFORE_SWAP_FLAG) {
                return (salt, hookAddr);
            }
        }
        revert HookSaltNotFound();
    }

    function _computeCreate2Address(address deployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash));
        return address(uint160(uint256(hash)));
    }
}
