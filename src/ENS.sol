// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ENSNamehash {
    function namehash(string memory name) internal pure returns (bytes32) {
        bytes32 node = bytes32(0);
        if (bytes(name).length == 0) {
            return node;
        }
        uint256 labelStart = 0;
        bytes memory nameBytes = bytes(name);
        for (uint256 i = 0; i <= nameBytes.length; i++) {
            if (i == nameBytes.length || nameBytes[i] == '.') {
                uint256 labelLen = i - labelStart;
                bytes32 labelHash = keccak256(slice(nameBytes, labelStart, labelLen));
                node = keccak256(abi.encodePacked(node, labelHash));
                labelStart = i + 1;
            }
        }
        return node;
    }

    function slice(bytes memory data, uint256 start, uint256 len) private pure returns (bytes memory) {
        bytes memory out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = data[start + i];
        }
        return out;
    }
}
