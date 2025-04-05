// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

// This contract is a "Escrow Agent" contract with the following features:
// * Deposit funds in escrow
// * Reject deposit if there was an error
// * Withdraw funds from escrow
// * Release funds after being successful
// TODO:
// - add deadlineDate
// - multiple agreements
// - dispute resolvance if arbitrator isn't agreed or arbitrator isn't active (get arbitrator from the pool)
// - funds distribution in dispute
// - register to the pool
// - erc20 support
// - min deposited funds
// 
contract EscrowAgent {

    uint256 public constant FUNDS_AUTORELEASED = 30 days;
    
    mapping (uint256 => Agreement) internal _escrow;
    mapping (uint256 => Dispute) internal _disputes;
    address[] internal _arbitratorsPool;

    uint256 private _agreementCounter;

    enum Status {
        Funded, // dep
        Canceled, // dep
        Rejected, // ben
        Active, // ben
        Refunded, // ben
        Closed, // dep
        Disputed, // dep
        Resolved, // arb
        Withdrawn // dep, ben, arb
    }

    struct Agreement {
        Status status;
        uint256 amount;
        address payable depositor;
        address payable beneficiary;
        uint256 startDate;
    }

    struct Dispute {
        address payable arbitrator;
        uint256 feePercentage;
        bool agreed;
    }

    event AgreementCreated(address indexed depositor, address indexed beneficiary, uint256 indexed agreementId, uint256 amount);
    event AgreementCanceled(uint256 indexed agreementId);
    event AgreementApproved(uint256 indexed agreementId);
    event AgreementRejected(uint256 indexed agreementId);
    event AgreementRefunded(uint256 indexed agreementId);
    event FundsAdded(uint256 indexed agreementId, address indexed sender, uint256 amount, uint256 totalAmount);
    event FundsWithdrawed(uint256 indexed agreementId, address indexed receiver, uint256 amount);
    event FundsReleased(uint256 indexed agreementId);
    event DisputeRaised(uint256 indexed agreementId);
    event DisputeResolved(uint256 indexed agreementId);
    event ArbitratorAgreed(uint256 indexed agreementId, address indexed arbitrator, bool agreed);

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

    function createAgreement(address payable _beneficiary) public payable {
        _agreementCounter++;
        // TODO: multiple agreements
        _escrow[_agreementCounter] = Agreement({
            status: Status.Funded, 
            amount: msg.value,
            depositor: payable(msg.sender),
            beneficiary: _beneficiary,
            startDate: block.timestamp
        });
        emit AgreementCreated(msg.sender, _beneficiary, _agreementCounter, msg.value);
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

    function withdrawFunds(uint256 agreementId) public payable {
        Agreement memory agreement = _escrow[agreementId];
        if (agreement.beneficiary == msg.sender && agreement.status == Status.Closed) {
            agreement.beneficiary.transfer(_escrow[agreementId].amount);
            _escrow[agreementId].status = Status.Withdrawn;
            emit FundsWithdrawed(agreementId, msg.sender, _escrow[agreementId].amount);
        } else if (agreement.depositor == msg.sender && (
                agreement.status == Status.Canceled || 
                agreement.status == Status.Rejected || 
                agreement.status == Status.Refunded)) {
            agreement.depositor.transfer(_escrow[agreementId].amount);
            _escrow[agreementId].status = Status.Withdrawn;
            emit FundsWithdrawed(agreementId, msg.sender, _escrow[agreementId].amount);
        }
        revert("You cannot widthraw funds");
    }

    function registerArbitrator(uint256 agreementId, address payable arbitrator) public 
            onlyDepositorOrBeneficiary(agreementId) inStatus(Status.Disputed, agreementId) {
        // check dispute exists
        if (_disputes[agreementId].arbitrator == address(0)) {
            if (_escrow[agreementId].depositor == msg.sender) {
                _disputes[agreementId] = Dispute({
                    arbitrator: arbitrator,
                    feePercentage: 100,
                    agreed: false
                });
                emit ArbitratorAgreed(agreementId, arbitrator, false);
            } else {
                revert("Only contractor can initialize the arbitrator");
            }
        } else {
            if (_escrow[agreementId].depositor == msg.sender) {
                if (_disputes[agreementId].arbitrator != arbitrator) {
                    _disputes[agreementId].agreed = false;
                    _disputes[agreementId].arbitrator = arbitrator;
                    emit ArbitratorAgreed(agreementId, arbitrator, false);
                }
            } else {
                if (_disputes[agreementId].arbitrator == arbitrator) {
                    // depositor set an arbitrator, beneficiary - agrees
                    _disputes[agreementId].agreed = true;
                    emit ArbitratorAgreed(agreementId, arbitrator, true);
                } else {
                    revert("The arbitrator address should be the same");
                }
            }
        }
    }

    function releaseFunds(uint256 agreementId) public 
            onlyDepositorOrBeneficiary(agreementId) inStatus(Status.Active, agreementId) {
        if (msg.sender == _escrow[agreementId].beneficiary) {
            require(block.timestamp >= _escrow[agreementId].startDate + FUNDS_AUTORELEASED, "Funds are still locked");
        }
        _escrow[agreementId].status = Status.Closed;
        emit FundsReleased(agreementId);
    }

    function raiseDispute(uint256 agreementId) public 
            onlyDepositor(agreementId) inStatus(Status.Active, agreementId) {
        _escrow[agreementId].status = Status.Disputed;
        emit DisputeRaised(agreementId);
    }

    function resolveDispute(uint256 agreementId) public
            onlyArbitrator(agreementId) inStatus(Status.Disputed, agreementId) {
        _escrow[agreementId].status = Status.Resolved;
        emit DisputeResolved(agreementId);
    }

    function getAgreementStatus(uint256 agreementId) external view returns (Status status) {
        return _escrow[agreementId].status;
    }
}