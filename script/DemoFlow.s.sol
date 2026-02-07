// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ENSNamehash} from "../src/ENS.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";
import {MockENSRegistry, MockENSResolver, MockPoolManager, SwapExecutor} from "./ScriptMocks.sol";

contract DemoFlow is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address trader = vm.envOr("DEMO_TRADER", address(0xBEEF));

        vm.startBroadcast(deployerKey);

        MockENSRegistry ens = new MockENSRegistry();
        MockENSResolver resolver = new MockENSResolver();
        MockPoolManager poolManager = new MockPoolManager();
        PolicyRegistry registry = new PolicyRegistry(address(ens));
        UniswapExeGuard hook = new UniswapExeGuard(address(poolManager), address(registry), 100, 30);
        SwapExecutor executor = new SwapExecutor();

        bytes32 node = ENSNamehash.namehash("alice.eth");
        ens.setResolver(node, address(resolver));
        resolver.setAddr(node, payable(trader));

        registry.setPolicyForENS("alice.eth", 100, 30);

        // Allowed swap attempt.
        executor.trySwap(address(poolManager), address(hook), trader, 80);

        // Blocked swap attempt (max swap violation).
        executor.trySwap(address(poolManager), address(hook), trader, 150);

        vm.stopBroadcast();

        console2.log("Demo deployed");
        console2.log("ENS registry:", address(ens));
        console2.log("PolicyRegistry:", address(registry));
        console2.log("UniswapExeGuard:", address(hook));
        console2.log("PoolManager:", address(poolManager));
        console2.log("SwapExecutor:", address(executor));
        console2.log("Trader:", trader);
        console2.log("Check broadcast logs for tx hashes and SwapExecutor.SwapAttempt events");
    }
}
