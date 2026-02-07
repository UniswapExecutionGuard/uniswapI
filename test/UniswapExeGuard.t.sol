// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";
import {ENSNamehash} from "../src/ENS.sol";
import {ENS} from "../lib/ens-contracts/contracts/registry/ENS.sol";
import {IAddrResolver} from "../lib/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";

interface Vm {
    function warp(uint256) external;
    function expectRevert(bytes calldata) external;
}

contract TestUtils {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        require(a == b, err);
    }

    function assertEq(address a, address b, string memory err) internal pure {
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
    function swap(address hook, address trader, int256 amountSpecified) external {
        PoolKey memory key;
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0});
        UniswapExeGuard(hook).beforeSwap(trader, key, params, "");
    }
}

contract UniswapExeGuardTest is TestUtils {
    MockENSRegistry private ens;
    MockENSResolver private resolver;
    PolicyRegistry private registry;
    MockPoolManager private pool;
    UniswapExeGuard private hook;

    address private trader = address(0xBEEF);

    function setUp() public {
        ens = new MockENSRegistry();
        resolver = new MockENSResolver();
        registry = new PolicyRegistry(address(ens));
        pool = new MockPoolManager();
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
        registry.setPolicy(trader, 200, 10);
        pool.swap(address(hook), trader, 150);
    }

    function testRevertWhenExceedsMaxSwap() public {
        registry.setPolicy(trader, 100, 0);
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.MaxSwapExceeded.selector, 100, 150));
        pool.swap(address(hook), trader, 150);
    }

    function testRevertWhenCooldownActive() public {
        registry.setPolicy(trader, 0, 20);
        pool.swap(address(hook), trader, 10);

        uint256 t0 = block.timestamp;
        vm.warp(t0 + 5);
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.CooldownNotElapsed.selector, t0 + 20, t0 + 5));
        pool.swap(address(hook), trader, 10);
    }

    function testDefaultsAppliedWhenNoPolicy() public {
        pool.swap(address(hook), trader, 50);
        vm.expectRevert(abi.encodeWithSelector(UniswapExeGuard.MaxSwapExceeded.selector, 100, 150));
        pool.swap(address(hook), trader, 150);
    }
}
