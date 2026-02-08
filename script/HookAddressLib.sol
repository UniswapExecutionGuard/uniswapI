// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library HookAddressLib {
    uint160 internal constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 internal constant BEFORE_SWAP_FLAG = uint160(1 << 7);

    function findBeforeSwapSalt(address deployer, bytes32 initCodeHash, uint256 maxSearch)
        internal
        pure
        returns (bytes32 salt, address hookAddr, bool found)
    {
        for (uint256 i = 0; i < maxSearch; i++) {
            salt = bytes32(i);
            hookAddr = computeCreate2Address(deployer, salt, initCodeHash);
            if ((uint160(hookAddr) & ALL_HOOK_MASK) == BEFORE_SWAP_FLAG) {
                return (salt, hookAddr, true);
            }
        }
        return (bytes32(0), address(0), false);
    }

    function computeCreate2Address(address deployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash));
        return address(uint160(uint256(hash)));
    }
}
