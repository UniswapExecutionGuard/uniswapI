// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ENSNamehash} from "../src/ENS.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";
import {HookDeployer} from "./HookDeployer.sol";
import {MockENSRegistry, MockENSResolver, MockPoolManager, SwapExecutor} from "./ScriptMocks.sol";

contract DemoFlow is Script {
    uint160 private constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 private constant BEFORE_SWAP_FLAG = uint160(1 << 7);
    uint256 private constant MAX_SALT_SEARCH = 500_000;

    error HookSaltNotFound();
    error HookAddressMismatch(address expected, address actual);

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY_ANVIL");

        vm.startBroadcast(deployerKey);

        MockENSRegistry ens = new MockENSRegistry();
        MockENSResolver resolver = new MockENSResolver();
        MockPoolManager poolManager = new MockPoolManager();
        PolicyRegistry registry = new PolicyRegistry(address(ens));
        HookDeployer deployer = new HookDeployer();
        bytes memory hookCreationCode = abi.encodePacked(
            type(UniswapExeGuard).creationCode, abi.encode(address(poolManager), address(registry), 100, 30)
        );
        bytes32 initCodeHash = keccak256(hookCreationCode);
        (bytes32 salt, address predictedHookAddress) = _findSalt(address(deployer), initCodeHash);
        address deployedHookAddress = deployer.deploy(salt, hookCreationCode);
        if (deployedHookAddress != predictedHookAddress) {
            revert HookAddressMismatch(predictedHookAddress, deployedHookAddress);
        }
        UniswapExeGuard hook = UniswapExeGuard(deployedHookAddress);
        hook.validateHookAddress();
        SwapExecutor executor = new SwapExecutor();

        bytes32 node = ENSNamehash.namehash("alice.eth");
        ens.setResolver(node, address(resolver));
        resolver.setAddr(node, payable(address(executor)));
        registry.setPolicyForENS("alice.eth", 100, 30);

        // Allowed swap attempt.
        executor.trySwap(address(poolManager), address(hook), 80);

        // Blocked swap attempt (max swap violation).
        executor.trySwap(address(poolManager), address(hook), 150);

        vm.stopBroadcast();

        console2.log("Demo deployed");
        console2.log("ENS registry:", address(ens));
        console2.log("PolicyRegistry:", address(registry));
        console2.log("HookDeployer:", address(deployer));
        console2.log("UniswapExeGuard:", address(hook));
        console2.log("salt:");
        console2.logBytes32(salt);
        console2.log("PoolManager:", address(poolManager));
        console2.log("SwapExecutor:", address(executor));
        console2.log("Check broadcast logs for tx hashes and SwapExecutor.SwapAttempt events");
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
