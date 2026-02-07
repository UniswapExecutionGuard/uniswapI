// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";
import {ENSNamehash} from "../src/ENS.sol";
import {ENS} from "../lib/ens-contracts/contracts/registry/ENS.sol";
import {IAddrResolver} from "../lib/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";
import {IMsgSender} from "../lib/v4-periphery/src/interfaces/IMsgSender.sol";

interface Vm {
    function warp(uint256) external;
    function expectRevert(bytes calldata) external;
    function expectRevert() external;
}

contract TestUtils {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        require(a == b, err);
    }

    function assertTrue(bool v, string memory err) internal pure {
        require(v, err);
    }
}

contract MockENSRegistry is ENS {
    mapping(bytes32 => address) public resolvers;

    function setResolver(bytes32 node, address resolverAddr) external {
        resolvers[node] = resolverAddr;
    }

    function resolver(bytes32 node) external view returns (address) {
        return resolvers[node];
    }

    function owner(bytes32) external pure returns (address) {
        return address(0);
    }

    function ttl(bytes32) external pure returns (uint64) {
        return 0;
    }

    function recordExists(bytes32) external pure returns (bool) {
        return false;
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    function setRecord(bytes32, address, address, uint64) external {}
    function setSubnodeRecord(bytes32, bytes32, address, address, uint64) external {}

    function setSubnodeOwner(bytes32, bytes32, address) external pure returns (bytes32) {
        return bytes32(0);
    }
    function setOwner(bytes32, address) external {}
    function setTTL(bytes32, uint64) external {}
    function setApprovalForAll(address, bool) external {}
}

contract MockENSResolver is IAddrResolver {
    mapping(bytes32 => address) public addrs;

    function setAddr(bytes32 node, address payable addr_) external {
        addrs[node] = addr_;
    }

    function addr(bytes32 node) external view returns (address payable) {
        return payable(addrs[node]);
    }
}

contract MockPoolManager {
    function swap(address hook, int256 amountSpecified) external {
        PoolKey memory key;
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0});
        UniswapExeGuard(hook).beforeSwap(msg.sender, key, params, "");
    }

    function swapWithFee(address hook, int256 amountSpecified, uint24 fee) external {
        PoolKey memory key;
        key.fee = fee;
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0});
        UniswapExeGuard(hook).beforeSwap(msg.sender, key, params, "");
    }
}

contract SwapCaller {
    function swapViaPool(address pool, address hook, int256 amountSpecified) external {
        MockPoolManager(pool).swap(hook, amountSpecified);
    }

    function swapViaPoolWithFee(address pool, address hook, int256 amountSpecified, uint24 fee) external {
        MockPoolManager(pool).swapWithFee(hook, amountSpecified, fee);
    }
}

contract MockMsgSenderRouter is IMsgSender {
    address private currentSender;

    function msgSender() external view returns (address) {
        return currentSender;
    }

    function swapViaPool(address pool, address hook, int256 amountSpecified) external {
        currentSender = msg.sender;
        MockPoolManager(pool).swap(hook, amountSpecified);
        currentSender = address(0);
    }

    function swapViaPoolWithFee(address pool, address hook, int256 amountSpecified, uint24 fee) external {
        currentSender = msg.sender;
        MockPoolManager(pool).swapWithFee(hook, amountSpecified, fee);
        currentSender = address(0);
    }
}

contract NonOwnerCaller {
    function callSetPolicy(PolicyRegistry registry, address trader, uint256 maxSwapAbs, uint256 cooldownSeconds)
        external
    {
        registry.setPolicy(trader, maxSwapAbs, cooldownSeconds);
    }

    function callClearPolicy(PolicyRegistry registry, address trader) external {
        registry.clearPolicy(trader);
    }

    function callSetPolicyForENS(
        PolicyRegistry registry,
        string calldata name,
        uint256 maxSwapAbs,
        uint256 cooldownSeconds
    ) external {
        registry.setPolicyForENS(name, maxSwapAbs, cooldownSeconds);
    }

    function callSetDefaults(UniswapExeGuard hook, uint256 maxSwapAbs, uint256 cooldownSeconds) external {
        hook.setDefaults(maxSwapAbs, cooldownSeconds);
    }

    function callSetTrustedProvider(UniswapExeGuard hook, address provider, bool trusted) external {
        hook.setTrustedMsgSenderProvider(provider, trusted);
    }
}

contract UniswapExeGuardTest is TestUtils {
    MockENSRegistry private ens;
    MockENSResolver private resolver;
    PolicyRegistry private registry;
    MockPoolManager private pool;
    UniswapExeGuard private hook;
    SwapCaller private caller;

    address private trader = address(0xBEEF);

    function setUp() public {
        ens = new MockENSRegistry();
        resolver = new MockENSResolver();
        registry = new PolicyRegistry(address(ens));
        pool = new MockPoolManager();
        caller = new SwapCaller();
        hook = new UniswapExeGuard(address(pool), address(registry), 100, 30);
    }

    function testENSResolutionAndPolicySet() public {
        bytes32 node = ENSNamehash.namehash("alice.eth");
        ens.setResolver(node, address(resolver));
        resolver.setAddr(node, payable(trader));

        registry.setPolicyForENS("alice.eth", 500, 15);

        (uint256 maxSwapAbs, uint256 cooldownSeconds, bool exists) = registry.getPolicy(trader);
        assertTrue(exists, "policy missing");
        assertEq(maxSwapAbs, 500, "maxSwapAbs wrong");
        assertEq(cooldownSeconds, 15, "cooldown wrong");
    }

    function testAllowedSwapWithinLimits() public {
        registry.setPolicy(address(caller), 200, 10);
        caller.swapViaPool(address(pool), address(hook), 150);
    }

    function testRevertWhenExceedsMaxSwap() public {
        registry.setPolicy(address(caller), 100, 0);
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.MaxSwapExceeded.selector, 100, 150));
        caller.swapViaPool(address(pool), address(hook), 150);
    }

    function testRevertWhenCooldownActive() public {
        registry.setPolicy(address(caller), 0, 20);
        caller.swapViaPool(address(pool), address(hook), 10);

        uint256 t0 = block.timestamp;
        vm.warp(t0 + 5);
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.CooldownNotElapsed.selector, t0 + 20, t0 + 5));
        caller.swapViaPool(address(pool), address(hook), 10);
    }

    function testCooldownIsPoolSpecific() public {
        registry.setPolicy(address(caller), 0, 20);

        caller.swapViaPoolWithFee(address(pool), address(hook), 10, 3000);
        uint256 t0 = block.timestamp;
        vm.warp(t0 + 5);

        // Different pool fee => different pool id, so cooldown should not block this swap.
        caller.swapViaPoolWithFee(address(pool), address(hook), 10, 500);

        // Same pool as the first swap should still be in cooldown.
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.CooldownNotElapsed.selector, t0 + 20, t0 + 5));
        caller.swapViaPoolWithFee(address(pool), address(hook), 10, 3000);
    }

    function testDefaultsAppliedWhenNoPolicy() public {
        caller.swapViaPool(address(pool), address(hook), 50);
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.MaxSwapExceeded.selector, 100, 150));
        caller.swapViaPool(address(pool), address(hook), 150);
    }

    function testHookPermissionsDeclaration() public view {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.beforeSwap, "beforeSwap permission should be enabled");
        assertTrue(!p.afterSwap, "afterSwap permission should be disabled");
        assertTrue(!p.beforeSwapReturnDelta, "beforeSwapReturnDelta should be disabled");
    }

    function testValidateHookAddressRevertsForNonFlaggedAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, address(hook)));
        hook.validateHookAddress();
    }

    function testRevertWhenENSUnresolved() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.EnsUnresolved.selector));
        registry.setPolicyForENS("unknown.eth", 100, 10);
    }

    function testRevertWhenAmountSpecifiedIsMinInt() public {
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.AmountSpecifiedInvalid.selector));
        caller.swapViaPool(address(pool), address(hook), type(int256).min);
    }

    function testTrustedMsgSenderProviderUsesOriginalCallerPolicy() public {
        MockMsgSenderRouter router = new MockMsgSenderRouter();

        // Router has a strict policy; original caller has a loose policy.
        registry.setPolicy(address(router), 60, 0);
        registry.setPolicy(address(this), 200, 0);

        // Untrusted router: policy applies to router address, so this swap is blocked.
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.MaxSwapExceeded.selector, 60, 100));
        router.swapViaPool(address(pool), address(hook), 100);

        // Trusted router: policy applies to original caller via IMsgSender.msgSender().
        hook.setTrustedMsgSenderProvider(address(router), true);
        router.swapViaPool(address(pool), address(hook), 100);
    }

    function testRevertWhenTrustedMsgSenderProviderIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.ProviderZeroAddress.selector));
        hook.setTrustedMsgSenderProvider(address(0), true);
    }

    function testRevertWhenNonOwnerCallsAdminFunctions() public {
        NonOwnerCaller attacker = new NonOwnerCaller();

        vm.expectRevert();
        attacker.callSetPolicy(registry, address(caller), 10, 10);

        vm.expectRevert();
        attacker.callClearPolicy(registry, address(caller));

        vm.expectRevert();
        attacker.callSetPolicyForENS(registry, "alice.eth", 10, 10);

        vm.expectRevert();
        attacker.callSetDefaults(hook, 10, 10);

        vm.expectRevert();
        attacker.callSetTrustedProvider(hook, address(caller), true);
    }
}
