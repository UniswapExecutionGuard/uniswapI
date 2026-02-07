// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ENSNamehash {
    /// @notice Computes ENS namehash for a fully-qualified name like "alice.eth".
    /// @dev ENS namehash is recursive: hash(parentNode, keccak256(label)),
    /// so labels are applied from right to left (TLD -> subdomain).
    function namehash(string memory name) internal pure returns (bytes32) {
        bytes memory b = bytes(name);
        bytes32 node;
        uint256 i = b.length;
        while (i > 0) {
            uint256 labelEnd = i;
            while (i > 0 && b[i - 1] != ".") {
                unchecked {
                    --i;
                }
            }
            node = keccak256(abi.encodePacked(node, _labelhash(b, i, labelEnd)));
            if (i > 0) {
                unchecked {
                    --i;
                }
            }
        }
        return node;
    }

    /// @dev Returns keccak256 hash of a single label slice [start, end).
    function _labelhash(bytes memory data, uint256 start, uint256 end) private pure returns (bytes32 hash) {
        bytes memory out = new bytes(end - start);
        for (uint256 j = start; j < end; j++) {
            out[j - start] = data[j];
        }
        return keccak256(out);
    }
}
