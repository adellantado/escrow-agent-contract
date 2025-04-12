// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// This contract is a "Escrow Agent" contract with the following features:
// * Deposit funds in escrow
// * Reject/Cancel/Refund deposit if there was an error
// * Release funds on successful delivery
// * Raise a dispute if needed
// * Agree on arbitrator or get one assigned from the pool of arbitrators 
// * Withdraw funds from escrow
// TODO:
// - multiple agreements or escrow factory
// - register arbitrators to the pool
// - erc20 support
// - min deposited funds
// 
contract EscrowAgent is ReentrancyGuard {

    uint256 public constant DEFAULT_DEADLINE_DATE = 30 days;
    uint256 public constant RELEASE_FUNDS_AFTER_DEADLINE = 3 days;
    uint256 public constant AGREE_ON_ARBITRATOR_MAX_PERIOD = 2 days;
    uint256 public constant RESOLVE_DISPUTE_MAX_PERIOD = 2 days;
    uint256 public constant UNRESOLVED_DISPUTE_REFUND_PERCENTAGE = 500000;
    uint256 public constant DEFAULT_ARBITRATOR_PERCENTAGE = 10000;
    
    mapping (uint256 => Agreement) internal _escrow;
    mapping (uint256 => Dispute) internal _disputes;
    address[] internal _arbitratorsPool;

    uint256 private _agreementCounter;

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

    struct Agreement {
        // agreement status
        Status status;
        // eth amount 
        uint256 amount;
        // aka "buyer"
        address payable depositor;
        // aka "seller"
        address payable beneficiary;
        // agreement started at
        uint256 startDate;
        // end date for result delivery, aka "delivery date"
        uint256 deadlineDate;
        // ipfs CID
        string detailsHash;
    }

    struct Dispute {
        // either parties agree on arbitrator or it must be assigned from the pool of arbitrators
        address payable arbitrator;
        // fees for arbitrator
        uint256 feePercentage;
        // parties agree on arbitrator
        bool agreed;
        // dispute started at
        uint256 startDate;
        // arbitrator assignment from the pool
        uint256 assignedDate;
        // refund for depositor
        uint256 refundAmount;
        // fees for arbitrator
        uint256 feeAmount;
        // beneficiary's funds
        uint256 releasedAmount;
    }

    event AgreementCreated(address indexed depositor, address indexed beneficiary, 
        uint256 indexed agreementId, uint256 amount, uint256 deadlineDate, string detailsHash);
    event AgreementCanceled(uint256 indexed agreementId);
    event AgreementApproved(uint256 indexed agreementId);
    event AgreementRejected(uint256 indexed agreementId);
    event AgreementRefunded(uint256 indexed agreementId);
    event FundsAdded(uint256 indexed agreementId, address indexed sender, uint256 amount, uint256 totalAmount);
    event FundsWithdrawed(uint256 indexed agreementId, address indexed receiver, uint256 amount);
    event FundsReleased(uint256 indexed agreementId);
    event DisputeRaised(uint256 indexed agreementId);
    event DisputeResolved(uint256 indexed agreementId, uint256 refundPercentage, 
        uint256 feeAmount, uint256 refundAmount, uint256 releasedAmount);
    event DisputeUnresolved(uint256 indexed agreementId, uint256 refundPercentage, uint256 refundAmount);
    event ArbitratorAgreed(uint256 indexed agreementId, address indexed arbitrator, bool agreed);
    event PoolArbitratorAssigned(uint256 indexed agreementId, address indexed arbitrator);

    modifier onlyDepositor(uint256 agreementId) {
        require(msg.sender == address(_escrow[agreementId].depositor), "You are not the depositor.");
        _;
    }

    modifier onlyBeneficiary(uint256 agreementId) {
        require(msg.sender == address(_escrow[agreementId].beneficiary), "You are not the beneficiary.");
        _;
    }

    modifier onlyDepositorOrBeneficiary(uint256 agreementId) {
        require(msg.sender == address(_escrow[agreementId].depositor) || 
            msg.sender == address(_escrow[agreementId].beneficiary), "You are not the depositor/beneficiary.");
        _;
    }

    modifier onlyArbitrator(uint256 agreementId) {
        require(msg.sender == address(_disputes[agreementId].arbitrator) &&
             _disputes[agreementId].agreed, "You are not the arbitrator.");
        _;
    }

    modifier inStatus(Status status, uint256 agreementId) {
        require(_escrow[agreementId].status == status, "The agreement is in a wrong status.");
        _;
    }

    constructor() {
        _arbitratorsPool.push(msg.sender);
    }

    function createAgreement(address payable _beneficiary, string memory detailsHash) public payable {
        createAgreement(_beneficiary, detailsHash, block.timestamp + DEFAULT_DEADLINE_DATE);
    }

    function createAgreement(address payable _beneficiary, string memory detailsHash, uint256 deadlineDate) public payable {
        _agreementCounter++;
        // TODO: multiple agreements
        _escrow[_agreementCounter] = Agreement({
            status: Status.Funded, 
            amount: msg.value,
            depositor: payable(msg.sender),
            beneficiary: _beneficiary,
            startDate: block.timestamp,
            deadlineDate: deadlineDate,
            detailsHash: detailsHash
        });
        emit AgreementCreated(msg.sender, _beneficiary, _agreementCounter, msg.value, deadlineDate, detailsHash);
    }

    function cancelAgreement(uint256 agreementId) public 
            onlyDepositor(agreementId) inStatus(Status.Funded, agreementId) {
        _escrow[agreementId].status = Status.Canceled;
        emit AgreementCanceled(agreementId);
    }

    function approveAggrement(uint256 agreementId) public 
            onlyBeneficiary(agreementId) inStatus(Status.Funded, agreementId) {
        _escrow[agreementId].status = Status.Active;
        emit AgreementApproved(agreementId);
    }

    function rejectAgreement(uint256 agreementId) public 
            onlyBeneficiary(agreementId) inStatus(Status.Funded, agreementId) {
        _escrow[agreementId].status = Status.Rejected;
        emit AgreementRejected(agreementId);
    }

    function refundAgreement(uint256 agreementId) public 
            onlyBeneficiary(agreementId) inStatus(Status.Active, agreementId) {
        _escrow[agreementId].status = Status.Refunded;
        emit AgreementRefunded(agreementId);
    }

    function addFunds(uint256 agreementId) public payable
            onlyDepositor(agreementId) inStatus(Status.Funded, agreementId) {
        _escrow[agreementId].amount += msg.value;
        emit FundsAdded(agreementId, msg.sender, msg.value, _escrow[agreementId].amount+msg.value);
    }

    function withdrawFunds(uint256 agreementId) public payable nonReentrant {
        Agreement memory agreement = _escrow[agreementId];
        if (agreement.beneficiary == msg.sender) {
            if (agreement.status == Status.Closed) {
                require(_escrow[agreementId].amount > 0, "Funds are not available");
                uint256 amount = _escrow[agreementId].amount;
                _escrow[agreementId].amount = 0;
                agreement.beneficiary.transfer(amount);
                emit FundsWithdrawed(agreementId, msg.sender, amount);
            } else if (agreement.status == Status.Resolved) {
                require(_disputes[agreementId].releasedAmount > 0, "Funds are not available");
                uint256 releasedAmount = _disputes[agreementId].releasedAmount;
                _disputes[agreementId].releasedAmount = 0;
                agreement.beneficiary.transfer(releasedAmount);
                emit FundsWithdrawed(agreementId, msg.sender, releasedAmount);
            } else if (agreement.status == Status.Unresolved) {
                require(_disputes[agreementId].releasedAmount > 0, "Funds are not available");
                uint256 releasedAmount = _disputes[agreementId].releasedAmount;
                _disputes[agreementId].releasedAmount = 0;
                agreement.beneficiary.transfer(releasedAmount);
                emit FundsWithdrawed(agreementId, msg.sender, releasedAmount);
            }
        } else if (agreement.depositor == msg.sender) {
            if (agreement.status == Status.Canceled || agreement.status == Status.Rejected || 
                    agreement.status == Status.Refunded) {
                require(_escrow[agreementId].amount > 0, "Funds are not available");
                uint256 amount = _escrow[agreementId].amount;
                _escrow[agreementId].amount = 0;
                agreement.depositor.transfer(amount);
                emit FundsWithdrawed(agreementId, msg.sender, amount);
            } else if(agreement.status == Status.Resolved || agreement.status == Status.Unresolved) {
                require(_disputes[agreementId].refundAmount > 0, "Funds are not available");
                uint256 refundAmount = _disputes[agreementId].refundAmount;
                _disputes[agreementId].refundAmount = 0;
                agreement.depositor.transfer(refundAmount);
                emit FundsWithdrawed(agreementId, msg.sender, refundAmount);
            }
        } else if (_disputes[agreementId].arbitrator == msg.sender) {
            if (agreement.status == Status.Resolved) {
                require(_disputes[agreementId].feeAmount > 0, "Funds are not available");
                uint256 feeAmount = _disputes[agreementId].feeAmount;
                _disputes[agreementId].feeAmount = 0;
                _disputes[agreementId].arbitrator.transfer(feeAmount);
                emit FundsWithdrawed(agreementId, msg.sender, feeAmount);
            }
        }
        revert("You cannot widthraw funds");
    }

    function registerArbitrator(uint256 agreementId, address payable arbitrator, uint256 feePercentage) public 
            onlyDepositorOrBeneficiary(agreementId) inStatus(Status.Disputed, agreementId) {
        // After AGREE_ON_ARBITRATOR_PERIOD arbitrator forcefully assigned from the pool
        if (block.timestamp >= _disputes[agreementId].startDate + AGREE_ON_ARBITRATOR_MAX_PERIOD){
            assignArbitrator(agreementId);
            return;
        }
        require(feePercentage >= 0 && feePercentage <= 1000000, 
            "Fee percent should be between 0 and 1000000");
        if (msg.sender == _escrow[agreementId].depositor) {
            if (_disputes[agreementId].arbitrator != arbitrator) {
                _disputes[agreementId].agreed = false;
                _disputes[agreementId].arbitrator = arbitrator;
                _disputes[agreementId].feePercentage = feePercentage;
                emit ArbitratorAgreed(agreementId, arbitrator, false);
            }
        } else {
            if (_disputes[agreementId].arbitrator == arbitrator && 
                    _disputes[agreementId].feePercentage == feePercentage) {
                // depositor set an arbitrator, beneficiary - agrees
                _disputes[agreementId].agreed = true;
                emit ArbitratorAgreed(agreementId, arbitrator, true);
            } else {
                revert("The arbitrator address and fees should be the same");
            }
        }
    }

    function assignArbitrator(uint256 agreementId) public 
            onlyDepositorOrBeneficiary(agreementId) inStatus(Status.Disputed, agreementId) {
        if (_disputes[agreementId].agreed) {
            // if arbitrator is agreed on but he/she does nothing after 2 days - trigger arbitrator assigment from the pool
            require(block.timestamp >= _disputes[agreementId].startDate + AGREE_ON_ARBITRATOR_MAX_PERIOD + RESOLVE_DISPUTE_MAX_PERIOD, "Too early to assign artibrator from the pool");
        } else {
            // if arbitrator is not agreed we need to trigger assigment from the pool
            require(block.timestamp >= _disputes[agreementId].startDate + AGREE_ON_ARBITRATOR_MAX_PERIOD, "Too early to assign artibrator from the pool");
        }
        _disputes[agreementId].arbitrator = payable(_arbitratorsPool[0]);
        _disputes[agreementId].agreed = true;
        _disputes[agreementId].assignedDate = block.timestamp;
        emit PoolArbitratorAssigned(agreementId, _arbitratorsPool[0]);
    }

    function releaseFunds(uint256 agreementId) public 
            onlyDepositorOrBeneficiary(agreementId) inStatus(Status.Active, agreementId) {
        // release funds if there is no dispute
        if (msg.sender == _escrow[agreementId].beneficiary) {
            require(block.timestamp >= _escrow[agreementId].deadlineDate + RELEASE_FUNDS_AFTER_DEADLINE, "Funds will be released in 3 days after the deadline");
        }
        _escrow[agreementId].status = Status.Closed;
        emit FundsReleased(agreementId);
    }

    function raiseDispute(uint256 agreementId) public 
            onlyDepositor(agreementId) inStatus(Status.Active, agreementId) {
        _escrow[agreementId].status = Status.Disputed;
        _disputes[agreementId] = Dispute({
            arbitrator: payable(0),
            feePercentage: DEFAULT_ARBITRATOR_PERCENTAGE,
            feeAmount: 0,
            agreed: false,
            startDate: block.timestamp,
            assignedDate: 0,
            refundAmount: 0,
            releasedAmount: 0
        });
        emit DisputeRaised(agreementId);
    }

    function resolveDispute(uint256 agreementId) public
            onlyDepositorOrBeneficiary(agreementId) inStatus(Status.Disputed, agreementId) {
        // if pool arbitrator doesn't resolve the dispute - set Unresolved status and split the escrow
        require(block.timestamp >= _disputes[agreementId].assignedDate + RESOLVE_DISPUTE_MAX_PERIOD, 
            "You can resolve dispute yourself in 2 days after the pool arbitrator assignment date");
        _disputes[agreementId].refundAmount = _escrow[agreementId].amount * UNRESOLVED_DISPUTE_REFUND_PERCENTAGE / 1_000_000;
        _disputes[agreementId].releasedAmount = _escrow[agreementId].amount - _disputes[agreementId].refundAmount;
        _escrow[agreementId].status = Status.Unresolved;
        emit DisputeUnresolved(agreementId, UNRESOLVED_DISPUTE_REFUND_PERCENTAGE, _disputes[agreementId].refundAmount);
    }

    function resolveDispute(uint256 agreementId, uint256 refundPercentage) public
            onlyArbitrator(agreementId) inStatus(Status.Disputed, agreementId) {
        require(refundPercentage >= 0 && refundPercentage <= 1000000, "Refunded percent should be between 0 and 1000000");
        _disputes[agreementId].feeAmount = _escrow[agreementId].amount *  _disputes[agreementId].feePercentage / 1_000_000;
        _disputes[agreementId].refundAmount = (_escrow[agreementId].amount - _disputes[agreementId].feeAmount) * refundPercentage / 1_000_000;
        _disputes[agreementId].releasedAmount = _escrow[agreementId].amount - _disputes[agreementId].feeAmount - _disputes[agreementId].refundAmount;
        _escrow[agreementId].status = Status.Resolved;
        emit DisputeResolved(agreementId, refundPercentage, _disputes[agreementId].feeAmount, 
            _disputes[agreementId].refundAmount, _disputes[agreementId].releasedAmount);
    }

    function getWithdrawBalance(uint256 agreementId) external view 
            inStatus(Status.Disputed, agreementId) returns (uint256) {
        Agreement memory agreement = _escrow[agreementId];
        if (agreement.beneficiary == msg.sender) {
            if (agreement.status == Status.Closed) {
                require(_escrow[agreementId].amount > 0, "Funds are not available");
                return _escrow[agreementId].amount;
            } else if (agreement.status == Status.Resolved || agreement.status == Status.Unresolved) {
                require(_disputes[agreementId].releasedAmount > 0, "Funds are not available");
                return _disputes[agreementId].releasedAmount;
            }
        } else if (agreement.depositor == msg.sender) {
            if (agreement.status == Status.Canceled || agreement.status == Status.Rejected || 
                    agreement.status == Status.Refunded) {
                require(_escrow[agreementId].amount > 0, "Funds are not available");
                return _escrow[agreementId].amount;
            } else if(agreement.status == Status.Resolved || agreement.status == Status.Unresolved) {
                require(_disputes[agreementId].refundAmount > 0, "Funds are not available");
                return _disputes[agreementId].refundAmount;
            }
        } else if (_disputes[agreementId].arbitrator == msg.sender) {
            if (agreement.status == Status.Resolved) {
                require(_disputes[agreementId].feeAmount > 0, "Funds are not available");
                return _disputes[agreementId].feeAmount;
            }
        }
        revert("You cannot widthraw funds");
    }

    function getAgreementDetails(uint256 agreementId) external view 
            returns (string memory, uint256, uint256, uint256) {
        require(msg.sender == address(_escrow[agreementId].depositor) || 
            msg.sender == address(_escrow[agreementId].beneficiary) ||
            msg.sender == address(_disputes[agreementId].arbitrator), 
            "You are not the depositor/beneficiary.");
        return (_escrow[agreementId].detailsHash, _escrow[agreementId].amount, 
            _escrow[agreementId].startDate, _escrow[agreementId].deadlineDate);
    }

    function getAgreementStatus(uint256 agreementId) external view returns (Status) {
        return _escrow[agreementId].status;
    }
}