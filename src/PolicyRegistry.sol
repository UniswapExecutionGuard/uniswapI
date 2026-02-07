// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ENS} from "../lib/ens-contracts/contracts/registry/ENS.sol";
import {IAddrResolver} from "../lib/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {Ownable} from "../lib/v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ENSNamehash} from "./ENS.sol";

contract PolicyRegistry is Ownable {
    struct Policy {
        uint256 maxSwapAbs;
        uint256 cooldownSeconds;
        bool exists;
    }

    ENS public immutable ens;

    mapping(address => Policy) private policies;

    event PolicySet(address indexed trader, uint256 maxSwapAbs, uint256 cooldownSeconds);
    event PolicyCleared(address indexed trader);

    constructor(address ensRegistry) Ownable(msg.sender) {
        require(ensRegistry != address(0), "ENS_ZERO");
        ens = ENS(ensRegistry);
    }

    function setPolicy(address trader, uint256 maxSwapAbs, uint256 cooldownSeconds) external onlyOwner {
        require(trader != address(0), "TRADER_ZERO");
        policies[trader] = Policy(maxSwapAbs, cooldownSeconds, true);
        emit PolicySet(trader, maxSwapAbs, cooldownSeconds);
    }

    function setPolicyForENS(string calldata name, uint256 maxSwapAbs, uint256 cooldownSeconds) external onlyOwner {
        address trader = resolveENS(name);
        require(trader != address(0), "ENS_UNRESOLVED");
        policies[trader] = Policy(maxSwapAbs, cooldownSeconds, true);
        emit PolicySet(trader, maxSwapAbs, cooldownSeconds);
    }

    function clearPolicy(address trader) external onlyOwner {
        require(trader != address(0), "TRADER_ZERO");
        delete policies[trader];
        emit PolicyCleared(trader);
    }

    function getPolicy(address trader)
        external
        view
        returns (uint256 maxSwapAbs, uint256 cooldownSeconds, bool exists)
    {
        Policy memory p = policies[trader];
        return (p.maxSwapAbs, p.cooldownSeconds, p.exists);
    }

    function resolveENS(string memory name) public view returns (address) {
        bytes32 node = ENSNamehash.namehash(name);
        address resolver = ens.resolver(node);
        if (resolver == address(0)) return address(0);
        return address(IAddrResolver(resolver).addr(node));
    }
}
