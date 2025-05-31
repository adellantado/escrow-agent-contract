// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "./MultisigEscrow.sol";

contract MultisigEscrowFactory {
    
    event EscrowCreated(address indexed escrow, address indexed depositor, address indexed beneficiary);

    function createEscrow(address payable beneficiary, uint32 deadlineDate) public payable returns (address) {
        MultisigEscrow escrow = new MultisigEscrow{value: msg.value}(
            beneficiary,
            deadlineDate
        );
        emit EscrowCreated(address(escrow), msg.sender, beneficiary);
        return address(escrow);
    }
} 