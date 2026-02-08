// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ENS} from "../lib/ens-contracts/contracts/registry/ENS.sol";
import {IAddrResolver} from "../lib/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {Ownable} from "../lib/v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ENSNamehash} from "./ENS.sol";

/**
 * @title PolicyRegistry
 * @notice Owner-managed storage for trader execution policies.
 * @dev ENS names are resolved only during policy setup, never during swap execution.
 */
contract PolicyRegistry is Ownable {
    error EnsZeroAddress();
    error TraderZeroAddress();
    error EnsUnresolved();

    struct Policy {
        uint256 maxSwapAbs; //maximum absolute value allowed in a swap
        uint256 cooldownSeconds; //minimum seconds between swaps for the trader
        bool exists; //default value=false means no policy
    }

    ENS private immutable ens;

    // Policies are configured here and consumed by the hook during beforeSwap.
    mapping(address trader => Policy) private policies;

    event PolicySet(address indexed trader, uint256 maxSwapAbs, uint256 cooldownSeconds);
    event PolicyCleared(address indexed trader);

    constructor(address ensRegistry) Ownable(msg.sender) {
        if (ensRegistry == address(0)) revert EnsZeroAddress();
        ens = ENS(ensRegistry);
    }

    function setPolicy(address trader, uint256 maxSwapAbs, uint256 cooldownSeconds) external onlyOwner {
        if (trader == address(0)) revert TraderZeroAddress();
        _writePolicy(trader, maxSwapAbs, cooldownSeconds);
    }

    function setPolicyForENS(string memory name, uint256 maxSwapAbs, uint256 cooldownSeconds) external onlyOwner {
        _setPolicyForNode(ENSNamehash.namehash(name), maxSwapAbs, cooldownSeconds);
    }

    /// @notice Sets policy by precomputed ENS node (namehash), avoiding string normalization mismatches.
    function setPolicyForNode(bytes32 node, uint256 maxSwapAbs, uint256 cooldownSeconds) external onlyOwner {
        _setPolicyForNode(node, maxSwapAbs, cooldownSeconds);
    }

    function clearPolicy(address trader) external onlyOwner {
        if (trader == address(0)) revert TraderZeroAddress();
        delete policies[trader];
        emit PolicyCleared(trader);
    }

    /// @notice Returns policy for trader.
    /// @dev Missing entries return Solidity defaults: (0, 0, false).
    function getPolicy(address trader)
        external
        view
        returns (uint256 maxSwapAbs, uint256 cooldownSeconds, bool exists)
    {
        Policy memory p = policies[trader];
        return (p.maxSwapAbs, p.cooldownSeconds, p.exists);
    }

    function resolveENS(string memory name) external view returns (address) {
        return resolveNode(ENSNamehash.namehash(name));
    }

    function resolveNode(bytes32 node) public view returns (address) {
        address resolver = ens.resolver(node);
        if (resolver == address(0)) return address(0);
        return address(IAddrResolver(resolver).addr(node));
    }

    function _setPolicyForNode(bytes32 node, uint256 maxSwapAbs, uint256 cooldownSeconds) internal {
        address resolvedTrader = resolveNode(node);
        if (resolvedTrader == address(0)) revert EnsUnresolved();
        _writePolicy(resolvedTrader, maxSwapAbs, cooldownSeconds);
    }

    function _writePolicy(address trader, uint256 maxSwapAbs, uint256 cooldownSeconds) internal {
        policies[trader] = Policy(maxSwapAbs, cooldownSeconds, true);
        emit PolicySet(trader, maxSwapAbs, cooldownSeconds);
    }
}
