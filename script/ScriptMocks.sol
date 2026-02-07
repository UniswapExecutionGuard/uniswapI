// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IENSRegistry, IENSResolver} from "../src/ENS.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";

contract MockENSRegistry is IENSRegistry {
    mapping(bytes32 => address) public resolvers;

    function setResolver(bytes32 node, address resolverAddr) external {
        resolvers[node] = resolverAddr;
    }

    function resolver(bytes32 node) external view returns (address) {
        return resolvers[node];
    }
}

contract MockENSResolver is IENSResolver {
    mapping(bytes32 => address) public addrs;

    function setAddr(bytes32 node, address addr_) external {
        addrs[node] = addr_;
    }

    function addr(bytes32 node) external view returns (address) {
        return addrs[node];
    }
}

contract MockPoolManager {
    function swap(address hook, address trader, int256 amountSpecified) external {
        UniswapExeGuard(hook).beforeSwap(trader, amountSpecified);
    }
}

contract SwapExecutor {
    event SwapAttempt(bool success, bytes returndata);

    function trySwap(address poolManager, address hook, address trader, int256 amountSpecified)
        external
        returns (bool success, bytes memory returndata)
    {
        (success, returndata) = poolManager.call(
            abi.encodeWithSignature("swap(address,address,int256)", hook, trader, amountSpecified)
        );
        emit SwapAttempt(success, returndata);
    }
}
