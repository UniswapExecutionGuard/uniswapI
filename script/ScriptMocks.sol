// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ENS} from "../lib/ens-contracts/contracts/registry/ENS.sol";
import {IAddrResolver} from "../lib/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";

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
}

contract SwapExecutor {
    event SwapAttempt(bool success, bytes returndata);

    function trySwap(address poolManager, address hook, int256 amountSpecified)
        external
        returns (bool success, bytes memory returndata)
    {
        (success, returndata) = poolManager.call(abi.encodeWithSignature("swap(address,int256)", hook, amountSpecified));
        emit SwapAttempt(success, returndata);
    }
}
