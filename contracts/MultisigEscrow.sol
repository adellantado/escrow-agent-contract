// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract MultisigEscrow is ReentrancyGuard, Pausable {

    struct Agreement {

        // 1st slot (20 bytes)
        // aka "buyer"
        address payable depositor;

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
        Revoked,
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
    event AgreementRevoked();
    event AgreementApproved();
    event AgreementRejected();
    event AgreementRefunded();
    event FundsAdded(uint96 amount, uint256 totalAmount);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    event FundsReleased();
    event FundsLocked();
    event MultisigSet(address indexed multisig);
    event MultisigApproved(address indexed multisig);
    event FundsCompensated(uint256 amount);

    modifier checkAddress(address user) {
        require(user != address(0), "zero address");
        _;
    }

    modifier onlyDepositor() {
        require(_msgSender() == address(_agreement.depositor), "only depositor");
        _;
    }

    modifier onlyBeneficiary() {
        require(_msgSender() == address(_agreement.beneficiary), "only beneficiary");
        _;
    }

    modifier onlyDepositorOrBeneficiary() {
        require(_msgSender() == address(_agreement.depositor) || 
            _msgSender() == address(_agreement.beneficiary), "only depositor/beneficiary.");
        _;
    }

    modifier inStatus(Status status) {
        require(_agreement.status == status, "wrong status");
        _;
    }

    modifier onlyMultisig() {
        require(_msgSender() == _agreement.multisig, "only multisig");
        _;
    }

    constructor(
        address payable beneficiary,
        uint32 deadlineDate
    ) payable checkAddress(beneficiary) {
        _agreement = Agreement({
            depositor: payable(_msgSender()),
            beneficiary: beneficiary,
            deadlineDate: deadlineDate,
            startDate: uint32(block.timestamp),
            status: Status.Funded,
            multisig: address(0),
            approved: false
        });
        emit AgreementCreated(_msgSender(), beneficiary, uint96(msg.value), deadlineDate);
    }

    receive() external payable onlyDepositor inStatus(Status.Funded) {
        emit FundsAdded(uint96(msg.value), address(this).balance);
    }

    function revokeAgreement() external onlyDepositor inStatus(Status.Funded) {
        _agreement.status = Status.Revoked;
        emit AgreementRevoked();
    }

    function approveAgreement() external onlyBeneficiary inStatus(Status.Funded) {
        _agreement.status = Status.Active;
        emit AgreementApproved();
    }

    function rejectAgreement() external onlyBeneficiary inStatus(Status.Funded) {
        _agreement.status = Status.Rejected;
        emit AgreementRejected();
    }

    function refundAgreement() external onlyBeneficiary inStatus(Status.Active) {
        _agreement.status = Status.Refunded;
        emit AgreementRefunded();
    }

    function releaseFunds() external onlyDepositorOrBeneficiary inStatus(Status.Active) {
        if (_msgSender() == _agreement.beneficiary) {
            require(block.timestamp >= _agreement.deadlineDate + RELEASE_FUNDS_AFTER_DEADLINE, 
                "can be released after: deadline + 3 days");
        }
        _agreement.status = Status.Closed;
        emit FundsReleased();
    }

    function withdrawFunds() external payable onlyBeneficiary inStatus(Status.Closed) nonReentrant {
        require(address(this).balance > 0, "funds not available");
        (bool success, ) =  _agreement.beneficiary.call{value: address(this).balance}("");
        require(success, "transfer failed");
        emit FundsWithdrawn(_msgSender(), address(this).balance);
        _pause();
    }

    function removeFunds() external payable onlyDepositor nonReentrant {
        require(_agreement.status == Status.Revoked || _agreement.status == Status.Rejected || 
            _agreement.status == Status.Refunded, "wrong status");
        require(address(this).balance > 0, "funds not available");
        (bool success, ) =  _agreement.depositor.call{value: address(this).balance}("");
        require(success, "transfer failed");
        emit FundsWithdrawn(_msgSender(), address(this).balance);
        _pause();
    }

    function lockFunds() external onlyDepositor inStatus(Status.Active) {
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

    function compensateAgreement(uint256 amount) external payable 
            onlyMultisig inStatus(Status.Locked) nonReentrant {
        require(address(this).balance >= amount, "not enough funds");
        _agreement.status = Status.Closed;
        if (amount != 0) {
            (bool success, ) =  _agreement.depositor.call{value: amount}("");
            require(success, "transfer failed");
        }
        emit FundsCompensated(amount);
        if (address(this).balance == 0) {
            _pause();
        }
    }
    
    function getAgreementDetails() external view 
            onlyDepositorOrBeneficiary returns (uint256, uint256, uint256, Status, address, bool) {
        return (address(this).balance, _agreement.startDate, _agreement.deadlineDate, 
            _agreement.status, _agreement.multisig, _agreement.approved);
    }

    function getAgreementStatus() external view returns (Status) {
        return _agreement.status;
    }

    function pause() onlyDepositor whenNotPaused external {
        require(_agreement.status == Status.Revoked ||
                _agreement.status == Status.Rejected ||
                _agreement.status == Status.Refunded ||
                _agreement.status == Status.Closed,
            "must be in final state");
        require (address(this).balance == 0, "withdraw funds to pause");
        _pause();
    }

    function createAgreement(
        address payable beneficiary,
        uint32 deadlineDate
    ) external payable onlyDepositor whenPaused checkAddress(beneficiary) {
        _agreement.beneficiary = beneficiary;
        _agreement.deadlineDate = deadlineDate;
        _agreement.startDate = uint32(block.timestamp);
        _agreement.status = Status.Funded;
        _agreement.multisig = address(0);
        _agreement.approved = false;
        emit AgreementCreated(_msgSender(), beneficiary, uint96(msg.value), deadlineDate);
    }
} 