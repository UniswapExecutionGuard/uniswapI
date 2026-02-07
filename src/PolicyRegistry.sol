// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ENS} from "../lib/ens-contracts/contracts/registry/ENS.sol";
import {IAddrResolver} from "../lib/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {Ownable} from "../lib/v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ENSNamehash} from "./ENS.sol";

/**
 * @title PolicyRegistry
 * @author Narges H
 * @notice Centralized registry for execution policies that can be referenced by Uniswap v4 hooks.
 * @dev This contract is owned by a governance or admin address that has permission to set and clear policies.
 * It inherits from OpenZeppelin's Ownable for access control.
 * It uses ENS to allow setting policies for ENS names
 */

contract PolicyRegistry is Ownable {
    // Errors
    error EnsZeroAddress();
    error TraderZeroAddress();
    error EnsUnresolved();

    struct Policy {
        uint256 maxSwapAbs; //maximum absolute value allowed in a swap
        uint256 cooldownSeconds; //minimum seconds between swaps for the trader
        bool exists; //default value=false means no policy
    }

    ENS private immutable ens;

    // Policies are configured here and NOT on swap execution.
    mapping(address => Policy) private policies;

    event PolicySet(address indexed trader, uint256 maxSwapAbs, uint256 cooldownSeconds);
    event PolicyCleared(address indexed trader);

    constructor(address ensRegistry) Ownable(msg.sender) {
        require(ensRegistry != address(0), EnsZeroAddress());
        ens = ENS(ensRegistry);
    }

    function setPolicy(address trader, uint256 maxSwapAbs, uint256 cooldownSeconds) external onlyOwner {
        require(trader != address(0), TraderZeroAddress());
        policies[trader] = Policy(maxSwapAbs, cooldownSeconds, true);
        emit PolicySet(trader, maxSwapAbs, cooldownSeconds);
    }

    function setPolicyForENS(string memory name, uint256 maxSwapAbs, uint256 cooldownSeconds) external onlyOwner {
        address ensAddress = resolveENS(name);
        require(ensAddress != address(0), EnsUnresolved());
        policies[ensAddress] = Policy(maxSwapAbs, cooldownSeconds, true);
        emit PolicySet(ensAddress, maxSwapAbs, cooldownSeconds);
    }

    function clearPolicy(address trader) external onlyOwner {
        require(trader != address(0), TraderZeroAddress());
        delete policies[trader];
        emit PolicyCleared(trader);
    }

    /// @notice Returns policy for trader.
    /// @dev if no policy exists, the array policies will return (0, 0, false) as these are the default values for the Policy struct fields.
    function getPolicy(address trader)
        external
        view
        returns (uint256 maxSwapAbs, uint256 cooldownSeconds, bool exists)
    {
        Policy memory p = policies[trader];
        return (p.maxSwapAbs, p.cooldownSeconds, p.exists);
    }

    function resolveENS(string memory name) internal view returns (address) {
        bytes32 node = ENSNamehash.namehash(name);
        address resolver = ens.resolver(node);
        if (resolver == address(0)) return address(0);
        return address(IAddrResolver(resolver).addr(node));
    }
}
