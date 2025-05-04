// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import "./BaseEscrowAgent.sol";

// TODO:
// - send predefined set of arbitrators
// - randomly select arbitrator from the pool
// - add upgradability
contract SimpleEscrowAgent is BaseEscrowAgent {

    Agreement internal _agreement;
    Dispute internal _dispute;
    address[] internal _arbitratorsPool;

    event AgreementCreated(address indexed depositor, address indexed beneficiary, 
        uint96 amount, uint32 deadlineDate, string detailsHash);
    event AgreementCanceled();
    event AgreementApproved();
    event AgreementRejected();
    event AgreementRefunded();
    event FundsAdded(uint96 amount, uint96 totalAmount);
    event FundsWithdrawn(address indexed recipient, uint96 amount);
    event FundsReleased();
    event DisputeRaised();
    event DisputeResolved(uint32 refundPercentage, 
        uint96 feeAmount, uint96 refundAmount, uint96 releasedAmount);
    event DisputeUnresolved(uint32 refundPercentage, uint96 refundAmount);
    event ArbitratorAgreed(address indexed arbitrator, bool agreed);
    event PoolArbitratorAssigned(address indexed arbitrator);

    modifier onlyDepositor() {
        require(msg.sender == address(_agreement.depositor), "You are not the depositor.");
        _;
    }

    modifier onlyBeneficiary() {
        require(msg.sender == address(_agreement.beneficiary), "You are not the beneficiary.");
        _;
    }

    modifier onlyDepositorOrBeneficiary() {
        require(msg.sender == address(_agreement.depositor) || 
            msg.sender == address(_agreement.beneficiary), "You are not the depositor/beneficiary.");
        _;
    }

    modifier onlyArbitrator() {
        require(msg.sender == address(_dispute.arbitrator) &&
             _dispute.agreed, "You are not the arbitrator.");
        _;
    }

    modifier inStatus(Status status) {
        require(_agreement.status == status, "The agreement is in a wrong status.");
        _;
    }

    constructor(
        address payable beneficiary,
        string memory detailsHash,
        uint32 deadlineDate
    ) payable checkAddress(beneficiary) {
        _agreement = Agreement({
            depositor: payable(msg.sender),
            beneficiary: beneficiary,
            amount: uint96(msg.value),
            deadlineDate: deadlineDate,
            startDate: uint32(block.timestamp),
            status: Status.Funded,
            detailsHash: detailsHash
        });
        emit AgreementCreated(msg.sender, beneficiary, uint96(msg.value), deadlineDate, detailsHash);
    }

    receive() external payable {
        require(msg.sender == address(_agreement.depositor), "Only depositor can add funds");
        require(_agreement.status == Status.Funded, "Agreement must be in Funded state");
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
                "Funds will be released in 3 days after the deadline");
        }
        _agreement.status = Status.Closed;
        emit FundsReleased();
    }

    function raiseDispute() public onlyDepositor inStatus(Status.Active) {
        require(block.timestamp > _agreement.deadlineDate, "You cannot raise dispute before the deadline");
        _agreement.status = Status.Disputed;
        _dispute = Dispute({
            arbitrator: payable(0),
            feePercentage: DEFAULT_ARBITRATOR_PERCENTAGE,
            feeAmount: 0,
            agreed: false,
            startDate: uint32(block.timestamp),
            assignedDate: 0,
            refundAmount: 0,
            releasedAmount: 0
        });
        emit DisputeRaised();
    }

    function registerArbitrator(address payable arbitrator, uint32 feePercentage) public 
            onlyDepositorOrBeneficiary checkAddress(arbitrator) inStatus(Status.Disputed) {
        if (block.timestamp >= _dispute.startDate + AGREE_ON_ARBITRATOR_MAX_PERIOD) {
            assignArbitrator();
            return;
        }
        require(feePercentage >= 0 && feePercentage <= 1000000, 
            "Fee percent should be between 0 and 1000000");
        if (msg.sender == address(_agreement.depositor)) {
            if (_dispute.arbitrator != arbitrator) {
                _dispute.agreed = false;
                _dispute.arbitrator = arbitrator;
                _dispute.feePercentage = feePercentage;
                emit ArbitratorAgreed(arbitrator, false);
            }
        } else {
            if (_dispute.arbitrator != arbitrator ||
                    _dispute.feePercentage != feePercentage) {
                revert WrongArbitrator(_dispute.arbitrator, arbitrator,
                    _dispute.feePercentage, feePercentage);
            }
            _dispute.agreed = true;
            emit ArbitratorAgreed(arbitrator, true);
        }
    }

    function assignArbitrator() public onlyDepositorOrBeneficiary inStatus(Status.Disputed) {
        if (_dispute.agreed) {
            require(block.timestamp >= _dispute.startDate + AGREE_ON_ARBITRATOR_MAX_PERIOD + RESOLVE_DISPUTE_MAX_PERIOD, 
                "Too early to assign arbitrator from the pool");
        } else {
            require(block.timestamp >= _dispute.startDate + AGREE_ON_ARBITRATOR_MAX_PERIOD, 
                "Too early to assign arbitrator from the pool");
        }
        _dispute.arbitrator = payable(_arbitratorsPool[0]);
        _dispute.agreed = true;
        _dispute.assignedDate = uint32(block.timestamp);
        emit PoolArbitratorAssigned(_arbitratorsPool[0]);
    }

    function resolveDispute() public onlyDepositorOrBeneficiary inStatus(Status.Disputed) {
        require(_dispute.assignedDate != 0 && block.timestamp >= _dispute.assignedDate + RESOLVE_DISPUTE_MAX_PERIOD, 
            "You can resolve dispute yourself in 2 days after the pool arbitrator assignment date");
        _dispute.refundAmount = uint96(_agreement.amount * UNRESOLVED_DISPUTE_REFUND_PERCENTAGE / 1_000_000);
        _dispute.releasedAmount = _agreement.amount - _dispute.refundAmount;
        _agreement.status = Status.Unresolved;
        emit DisputeUnresolved(UNRESOLVED_DISPUTE_REFUND_PERCENTAGE, _dispute.refundAmount);
    }

    function resolveDispute(uint32 refundPercentage) public onlyArbitrator inStatus(Status.Disputed) {
        require(refundPercentage >= 0 && refundPercentage <= 1000000, 
            "Refunded percent should be between 0 and 1000000");
        _dispute.feeAmount = uint96(_agreement.amount * _dispute.feePercentage / 1_000_000);
        _dispute.refundAmount = uint96((_agreement.amount - _dispute.feeAmount) * refundPercentage / 1_000_000);
        _dispute.releasedAmount = _agreement.amount - _dispute.feeAmount - _dispute.refundAmount;
        _agreement.status = Status.Resolved;
        emit DisputeResolved(refundPercentage, _dispute.feeAmount, 
            _dispute.refundAmount, _dispute.releasedAmount);
    }

    function withdrawFunds() public payable nonReentrant {
        if (msg.sender == _agreement.beneficiary) {
            if (_agreement.status == Status.Closed) {
                require(_agreement.amount > 0, "Funds are not available");
                uint96 amount = _agreement.amount;
                _agreement.amount = 0;
                _agreement.beneficiary.transfer(amount);
                emit FundsWithdrawn(msg.sender, amount);
                return;
            } else if (_agreement.status == Status.Resolved) {
                require(_dispute.releasedAmount > 0, "Funds are not available");
                uint96 releasedAmount = _dispute.releasedAmount;
                _dispute.releasedAmount = 0;
                _agreement.beneficiary.transfer(releasedAmount);
                emit FundsWithdrawn(msg.sender, releasedAmount);
                return;
            } else if (_agreement.status == Status.Unresolved) {
                require(_dispute.releasedAmount > 0, "Funds are not available");
                uint96 releasedAmount = _dispute.releasedAmount;
                _dispute.releasedAmount = 0;
                _agreement.beneficiary.transfer(releasedAmount);
                emit FundsWithdrawn(msg.sender, releasedAmount);
                return;
            }
        } else if (msg.sender == _agreement.depositor) {
            if (_agreement.status == Status.Canceled || _agreement.status == Status.Rejected || 
                    _agreement.status == Status.Refunded) {
                require(_agreement.amount > 0, "Funds are not available");
                uint96 amount = _agreement.amount;
                _agreement.amount = 0;
                _agreement.depositor.transfer(amount);
                emit FundsWithdrawn(msg.sender, amount);
                return;
            } else if(_agreement.status == Status.Resolved || _agreement.status == Status.Unresolved) {
                require(_dispute.refundAmount > 0, "Funds are not available");
                uint96 refundAmount = _dispute.refundAmount;
                _dispute.refundAmount = 0;
                _agreement.depositor.transfer(refundAmount);
                emit FundsWithdrawn(msg.sender, refundAmount);
                return;
            }
        } else if (_dispute.arbitrator == msg.sender) {
            if (_agreement.status == Status.Resolved) {
                require(_dispute.feeAmount > 0, "Funds are not available");
                uint96 feeAmount = _dispute.feeAmount;
                _dispute.feeAmount = 0;
                _dispute.arbitrator.transfer(feeAmount);
                emit FundsWithdrawn(msg.sender, feeAmount);
                return;
            }
        }
        revert WithdrawProhibited(msg.sender, _agreement.status);
    }

    function getWithdrawBalance() external view inStatus(Status.Disputed) returns (uint256) {
        if (msg.sender == _agreement.beneficiary) {
            if (_agreement.status == Status.Closed) {
                require(_agreement.amount > 0, "Funds are not available");
                return _agreement.amount;
            } else if (_agreement.status == Status.Resolved || _agreement.status == Status.Unresolved) {
                require(_dispute.releasedAmount > 0, "Funds are not available");
                return _dispute.releasedAmount;
            }
        } else if (msg.sender == _agreement.depositor) {
            if (_agreement.status == Status.Canceled || _agreement.status == Status.Rejected || 
                    _agreement.status == Status.Refunded) {
                require(_agreement.amount > 0, "Funds are not available");
                return _agreement.amount;
            } else if(_agreement.status == Status.Resolved || _agreement.status == Status.Unresolved) {
                require(_dispute.refundAmount > 0, "Funds are not available");
                return _dispute.refundAmount;
            }
        } else if (_dispute.arbitrator == msg.sender) {
            if (_agreement.status == Status.Resolved) {
                require(_dispute.feeAmount > 0, "Funds are not available");
                return _dispute.feeAmount;
            }
        }
        revert NoBalance(msg.sender, _agreement.status);
    }

    function getAgreementDetails() external view returns (string memory, uint256, uint256, uint256) {
        require(msg.sender == _agreement.depositor || 
            msg.sender == _agreement.beneficiary ||
            msg.sender == _dispute.arbitrator, 
            "You are not the depositor/beneficiary.");
        return (_agreement.detailsHash, _agreement.amount, 
            _agreement.startDate, _agreement.deadlineDate);
    }

    function getAgreementStatus() external view returns (Status) {
        return _agreement.status;
    }

    function destroy() external {
        require(_agreement.status == Status.Closed || 
                _agreement.status == Status.Canceled || 
                _agreement.status == Status.Rejected || 
                _agreement.status == Status.Refunded ||
                _agreement.status == Status.Resolved ||
                _agreement.status == Status.Unresolved,
            "Agreement must be in final state");
        require(_dispute.feeAmount == 0 && _dispute.releasedAmount == 0,
            "All funds must be withdrawn");
        selfdestruct(payable(_agreement.depositor));
    }
} 