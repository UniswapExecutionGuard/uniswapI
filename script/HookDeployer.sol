// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract HookDeployer {
    error DeploymentFailed();
    error OwnershipTransferFailed();

    function deploy(bytes32 salt, bytes memory creationCode) external returns (address deployed) {
        deployed = _deploy(salt, creationCode);
    }

    function deployAndTransferOwnership(bytes32 salt, bytes memory creationCode, address newOwner)
        external
        returns (address deployed)
    {
        deployed = _deploy(salt, creationCode);
        if (newOwner != address(0)) {
            (bool ok,) = deployed.call(abi.encodeWithSignature("transferOwnership(address)", newOwner));
            if (!ok) revert OwnershipTransferFailed();
        }
    }

    function _deploy(bytes32 salt, bytes memory creationCode) internal returns (address deployed) {
        assembly {
            deployed := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }
        if (deployed == address(0)) revert DeploymentFailed();
    }
}
