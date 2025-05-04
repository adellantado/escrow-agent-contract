// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import "./SimpleEscrowAgent.sol";

contract SimpleEscrowFactory {
    
    event EscrowCreated(address indexed escrow, address indexed depositor, address indexed beneficiary);

    function createEscrow(address payable beneficiary, string memory detailsHash, uint32 deadlineDate) public payable returns (address) {
        SimpleEscrowAgent escrow = new SimpleEscrowAgent{value: msg.value}(
            beneficiary,
            detailsHash,
            deadlineDate
        );
        emit EscrowCreated(address(escrow), msg.sender, beneficiary);
        return address(escrow);
    }
} 