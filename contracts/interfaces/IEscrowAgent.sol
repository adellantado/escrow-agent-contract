// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

interface IEscrowAgent {

    struct Agreement {

        // 1st slot (32 bytes)
        // aka "buyer"
        address payable depositor;
        // eth amount 
        uint96 amount;

        // 2nd slot (29 bytes)
        // aka "seller"
        address payable beneficiary;
        // end date for result delivery, aka "delivery date"
        uint32 deadlineDate;
        // agreement started at
        uint32 startDate;
        // agreement status
        Status status;

        // 3rd slot (32 bytes)
        // ipfs CID
        string detailsHash;
    }

    struct Dispute {

        // 4th slot (32 bytes)
        // either parties agree on arbitrator or it must be assigned from the pool of arbitrators
        address payable arbitrator;
        // fees for arbitrator
        uint32 feePercentage;
        // dispute started at
        uint32 startDate;
        // arbitrator assignment from the pool
        uint32 assignedDate;

        // 5th slot (24 bytes)
        // fees for arbitrator
        uint96 feeAmount;
        // refund for depositor
        uint96 refundAmount;

        // 6th slot (13 bytes)
        // beneficiary's funds
        uint96 releasedAmount;
        // parties agree on arbitrator
        bool agreed;
    }

    enum Status {
        // The workflow for an "Agreement"
        //
        // Funds added to the escrow
        // ||
        // \/
        Funded, // dep
        // ||
        // \/
        // Depositor changed his mind, if beneficiary haven't agreed yet
        Canceled, // dep
        // 
        // Funded 
        // ||
        // \/
        // Beneficiary rejected the agreement
        Rejected, // ben
        //
        // Funded
        // ||
        // \/
        // Beneficiary agreed on terms
        Active, // ben
        // ||
        // \/
        // Beneficiary decided to return funds
        Refunded, // ben
        //
        // Active
        // ||
        // \/
        // Depositor released the funds or the beneficiary claimed funds after the deadline
        Closed, // dep, ben
        //
        // Active
        // ||
        // \/
        // A dispute raised by the depositor 
        Disputed, // dep
        // ||
        // \/
        // The dispute resolved by the arbitrator
        Resolved, // arb
        // 
        // Disputed
        // ||
        // \/
        // The dispute wasn't resolved by the arbitrator
        Unresolved // dep, ben
    }

    // if beneficiary agrees on arbitrator with wrong address or fee percentage
    error WrongArbitrator(address oldArbitrator, address newArbitrator, uint32 oldFeePercentage, uint32 newFeePercentage);
    // can't show balance
    error NoBalance(address sender, Status status);
    // can't withdraw funds
    error WithdrawProhibited(address sender, Status status);
}