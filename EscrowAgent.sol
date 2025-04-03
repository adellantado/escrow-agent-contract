//SPDX-License-Identifier:MIT

pragma solidity ^0.8.26;

contract EscrowAgent {
    
    mapping (uint256 => Agreement) internal _escrow;
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
    }

    struct Dispute {
        address payable arbitrator;
        uint256 feePercentage;
    }

    event AgreementCreated(address indexed depositor, address indexed beneficiary, uint256 indexed agreementId, uint256 amount);
    event AgreementCanceled(uint256 indexed agreementId);
    event AgreementApproved(uint256 indexed agreementId);
    event AgreementRejected(uint256 indexed agreementId);
    event FundsAdded(uint256 indexed agreementId, address indexed sender, uint256 amount);
    event FundsWithdrawed(uint256 indexed agreementId, address indexed receiver, uint256 amount);
    event FundsReleased(uint256 indexed agreementId);
    event DisputeRaised(uint256 indexed agreementId);
    event DisputeResolved(uint256 indexed agreementId);

    modifier onlyDepositor(uint256 agreementId) {
        require(msg.sender == address(_escrow[agreementId].depositor), "You are not the depositor.");
        _;
    }

    modifier onlyBeneficiary(uint256 agreementId) {
        require(msg.sender == address(_escrow[agreementId].beneficiary), "You are not the beneficiary.");
        _;
    }

    modifier onlyArbitrator(uint256 agreementId) {
        require(msg.sender == address(_escrow[agreementId].beneficiary), "You are not the arbitrator.");
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
            beneficiary: _beneficiary
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

    function addFunds(uint256 agreementId, uint256 amount) public payable
            onlyDepositor(agreementId) inStatus(Status.Funded, agreementId) {
        emit FundsAdded(agreementId, msg.sender, amount);
    }

    function withdrawFunds(uint256 agreementId) public payable {
        Agreement memory agreement = _escrow[agreementId];
        if (agreement.beneficiary == msg.sender && agreement.status == Status.Closed) {
            agreement.beneficiary.transfer(_escrow[agreementId].amount);
            _escrow[agreementId].status = Status.Withdrawn;
            emit FundsWithdrawed(agreementId, msg.sender, _escrow[agreementId].amount);
        } else if (agreement.depositor == msg.sender && (agreement.status == Status.Canceled || agreement.status == Status.Rejected)) {
            agreement.depositor.transfer(_escrow[agreementId].amount);
            _escrow[agreementId].status = Status.Withdrawn;
            emit FundsWithdrawed(agreementId, msg.sender, _escrow[agreementId].amount);
        }
    }

    function registerArbitrator(uint256 agreementId) public {
        // TODO
    }

    function releaseFunds(uint256 agreementId) public 
            onlyDepositor(agreementId) inStatus(Status.Active, agreementId) {
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