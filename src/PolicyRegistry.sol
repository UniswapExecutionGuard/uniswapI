// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IENSRegistry, IENSResolver, ENSNamehash} from "./ENS.sol";
import {Ownable} from "./Ownable.sol";

contract PolicyRegistry is Ownable {
    struct Policy {
        uint256 maxSwapAbs;
        uint256 cooldownSeconds;
        bool exists;
    }

    IENSRegistry public immutable ens;

    mapping(address => Policy) private policies;

    event PolicySet(address indexed trader, uint256 maxSwapAbs, uint256 cooldownSeconds);
    event PolicyCleared(address indexed trader);

    constructor(address ensRegistry) {
        require(ensRegistry != address(0), "ENS_ZERO");
        ens = IENSRegistry(ensRegistry);
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

    function getPolicy(address trader) external view returns (uint256 maxSwapAbs, uint256 cooldownSeconds, bool exists) {
        Policy memory p = policies[trader];
        return (p.maxSwapAbs, p.cooldownSeconds, p.exists);
    }

    function resolveENS(string memory name) public view returns (address) {
        bytes32 node = ENSNamehash.namehash(name);
        address resolver = ens.resolver(node);
        if (resolver == address(0)) return address(0);
        return IENSResolver(resolver).addr(node);
    }
}
