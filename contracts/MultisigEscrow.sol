// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MultisigEscrow is ReentrancyGuard {

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

        // 3th slot (21 bytes)
        // multisig address set by beneficiary, needed only for dispute resolution
        // note: if needed this address could be set to arbitrator address
        address multisig;
        // depositor approves multisig set by beneficiary
        // note: if needed this could approve arbitrator set by the beneficiary 
        bool approved;
    }

    enum Status {
        // The workflow for an "Agreement"
        //
        // Funds added to the escrow
        // ||
        // \/
        Funded,
        // ||
        // \/
        // Depositor changed his mind, if beneficiary haven't agreed yet
        Canceled,
        // 
        // Funded 
        // ||
        // \/
        // Beneficiary rejected the agreement
        Rejected,
        //
        // Funded
        // ||
        // \/
        // Beneficiary agreed on terms
        Active,
        // ||
        // \/
        // Beneficiary decided to return funds
        Refunded,
        //
        // Active
        // ||
        // \/
        // Depositor released the funds or the beneficiary claimed funds after the deadline
        Closed,
        //
        // Active
        // ||
        // \/
        // Depositor locks the funds after the deadline
        Locked
    }

    uint256 public constant RELEASE_FUNDS_AFTER_DEADLINE = 3 days;

    Agreement internal _agreement;

    event AgreementCreated(address indexed depositor, address indexed beneficiary, 
        uint96 amount, uint32 deadlineDate);
    event AgreementCanceled();
    event AgreementApproved();
    event AgreementRejected();
    event AgreementRefunded();
    event FundsAdded(uint96 amount, uint96 totalAmount);
    event FundsWithdrawn(address indexed recipient, uint96 amount);
    event FundsReleased();
    event FundsLocked();
    event MultisigSet(address indexed multisig);
    event MultisigApproved(address indexed multisig);
    event FundsCompensated(uint96 amount);

    modifier checkAddress(address user) {
        require(user != address(0), "zero address");
        _;
    }

    modifier onlyDepositor() {
        require(msg.sender == address(_agreement.depositor), "only depositor");
        _;
    }

    modifier onlyBeneficiary() {
        require(msg.sender == address(_agreement.beneficiary), "only beneficiary");
        _;
    }

    modifier onlyDepositorOrBeneficiary() {
        require(msg.sender == address(_agreement.depositor) || 
            msg.sender == address(_agreement.beneficiary), "only depositor/beneficiary.");
        _;
    }

    modifier inStatus(Status status) {
        require(_agreement.status == status, "wrong status");
        _;
    }

    modifier onlyMultisig() {
        require(msg.sender == _agreement.multisig, "only multisig");
        _;
    }

    constructor(
        address payable beneficiary,
        uint32 deadlineDate
    ) payable checkAddress(beneficiary) {
        _agreement = Agreement({
            depositor: payable(msg.sender),
            beneficiary: beneficiary,
            amount: uint96(msg.value),
            deadlineDate: deadlineDate,
            startDate: uint32(block.timestamp),
            status: Status.Funded,
            multisig: address(0),
            approved: false
        });
        emit AgreementCreated(msg.sender, beneficiary, uint96(msg.value), deadlineDate);
    }

    receive() external payable onlyDepositor inStatus(Status.Funded) {
        _agreement.amount += uint96(msg.value);
        emit FundsAdded(uint96(msg.value), _agreement.amount);
    }

    function cancelAgreement() public onlyDepositor inStatus(Status.Funded) {
        _agreement.status = Status.Canceled;
        emit AgreementCanceled();
    }

    function approveAgreement() public onlyBeneficiary inStatus(Status.Funded) {
        _agreement.status = Status.Active;
        emit AgreementApproved();
    }

    function rejectAgreement() public onlyBeneficiary inStatus(Status.Funded) {
        _agreement.status = Status.Rejected;
        emit AgreementRejected();
    }

    function refundAgreement() public onlyBeneficiary inStatus(Status.Active) {
        _agreement.status = Status.Refunded;
        emit AgreementRefunded();
    }

    function releaseFunds() public onlyDepositorOrBeneficiary inStatus(Status.Active) {
        if (msg.sender == _agreement.beneficiary) {
            require(block.timestamp >= _agreement.deadlineDate + RELEASE_FUNDS_AFTER_DEADLINE, 
                "can be released after: deadline + 3 days");
        }
        _agreement.status = Status.Closed;
        emit FundsReleased();
    }

    function withdrawFunds() public payable onlyBeneficiary inStatus(Status.Closed) nonReentrant {
        require(_agreement.amount > 0, "funds not available");
        _agreement.amount = 0;
        _agreement.beneficiary.transfer(_agreement.amount);
        emit FundsWithdrawn(msg.sender, _agreement.amount);
    }

    function removeFunds() external onlyDepositor nonReentrant {
        require(_agreement.status == Status.Canceled || _agreement.status == Status.Rejected || 
            _agreement.status == Status.Refunded, "wrong status");
        require(_agreement.amount > 0, "funds not available");
        _agreement.amount = 0;
        _agreement.depositor.transfer(_agreement.amount);
        emit FundsWithdrawn(msg.sender, _agreement.amount);
    }

    function lockFunds() public onlyDepositor inStatus(Status.Active) {
        require(block.timestamp >= _agreement.deadlineDate &&
            block.timestamp < _agreement.deadlineDate + RELEASE_FUNDS_AFTER_DEADLINE, 
            "can be locked after deadline during 3 days");
        _agreement.status = Status.Locked;
        emit FundsLocked();
    }

    function setMultisig(address multisig) external 
            onlyBeneficiary checkAddress(multisig) inStatus(Status.Locked) {
        _agreement.multisig = multisig;
        emit MultisigSet(multisig);
    }

    function approveMultisig() external 
            onlyDepositor inStatus(Status.Locked) {
        require(_agreement.multisig != address(0), "multisig not set");
        _agreement.approved = true;
        emit MultisigApproved(_agreement.multisig);
    }

    function compensateAgreement(uint96 amount) external 
            onlyMultisig inStatus(Status.Locked) nonReentrant {
        require(_agreement.amount >= amount, "not enough funds");
        _agreement.amount -= amount;
        _agreement.status = Status.Closed;
        _agreement.depositor.transfer(amount);
        emit FundsCompensated(amount);
    }
    
    function getAgreementDetails() external view 
            onlyDepositorOrBeneficiary returns (uint256, uint256, uint256, Status, address, bool) {
        return (_agreement.amount, _agreement.startDate, _agreement.deadlineDate, 
            _agreement.status, _agreement.multisig, _agreement.approved);
    }

    function getAgreementStatus() external view returns (Status) {
        return _agreement.status;
    }

    function destroy() external {
        require(_agreement.status == Status.Closed || 
                _agreement.status == Status.Canceled || 
                _agreement.status == Status.Rejected || 
                _agreement.status == Status.Refunded,
            "Agreement must be in final state");
        selfdestruct(payable(_agreement.depositor));
    }
} 