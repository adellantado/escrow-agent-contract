// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import "./BaseEscrowAgent.sol";

// This contract is a "Escrow Agent" contract with the following features:
// * Deposit funds in escrow
// * Reject/Cancel/Refund deposit if there was an error
// * Release funds on successful delivery
// * Raise a dispute if needed
// * Agree on arbitrator or get one assigned from the pool of arbitrators
// * Withdraw funds from escrow
// TODO:
// - multiple agreements or escrow factory
// - erc20 support
// - min deposited funds
// - optimize gas
// 
contract EscrowAgent is BaseEscrowAgent {

    uint256 public constant DEFAULT_DEADLINE_DATE = 30 days;

    address internal immutable _owner;
    mapping(uint256 => Agreement) internal _escrow;
    mapping(uint256 => Dispute) internal _disputes;
    address[] internal _arbitratorsPool;
    mapping(address => uint256[]) internal _assignedAgreements;
    uint256 private _agreementCounter;

    // arbitrator is in the pool
    error ArbitratorInPool(address arbitrator);
    // arbitrator is not in the pool
    error ArbitratorNotInPool(address arbitrator);

    event AgreementCreated(address indexed depositor, address indexed beneficiary, 
        uint256 indexed agreementId, uint96 amount, uint32 deadlineDate, string detailsHash);
    event AgreementCanceled(uint256 indexed agreementId);
    event AgreementApproved(uint256 indexed agreementId);
    event AgreementRejected(uint256 indexed agreementId);
    event AgreementRefunded(uint256 indexed agreementId);
    event FundsAdded(uint256 indexed agreementId, address indexed sender, uint96 amount, uint96 totalAmount);
    event FundsWithdrawn(uint256 indexed agreementId, address indexed recipient, uint96 amount);
    event FundsReleased(uint256 indexed agreementId);
    event DisputeRaised(uint256 indexed agreementId);
    event DisputeResolved(uint256 indexed agreementId, uint32 refundPercentage, 
        uint96 feeAmount, uint96 refundAmount, uint96 releasedAmount);
    event DisputeUnresolved(uint256 indexed agreementId, uint32 refundPercentage, uint96 refundAmount);
    event ArbitratorAgreed(uint256 indexed agreementId, address indexed arbitrator, bool agreed);
    event PoolArbitratorAssigned(uint256 indexed agreementId, address indexed arbitrator);
    event PoolArbitratorAdded(address indexed arbitrator);
    event PoolArbitratorRemoved(address indexed arbitrator);

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

    modifier onlyOwner() {
        require(msg.sender == _owner, "You are not the owner.");
        _;
    }

    modifier inStatus(Status status, uint256 agreementId) {
        require(_escrow[agreementId].status == status, "The agreement is in a wrong status.");
        _;
    }

    constructor() {
        _owner = msg.sender;
    }

    function createAgreement(address payable _beneficiary, string memory detailsHash) public payable {
        createAgreement(_beneficiary, detailsHash, uint32(block.timestamp + DEFAULT_DEADLINE_DATE));
    }

    function createAgreement(address payable _beneficiary, string memory detailsHash, uint32 deadlineDate) public payable checkAddress(_beneficiary) {
        _agreementCounter++;
        // TODO: multiple agreements
        emit AgreementCreated(msg.sender, _beneficiary, _agreementCounter, uint96(msg.value), deadlineDate, detailsHash);
        _escrow[_agreementCounter] = Agreement({
            status: Status.Funded,
            depositor: payable(msg.sender),
            beneficiary: _beneficiary,
            amount: uint96(msg.value),
            deadlineDate: deadlineDate,
            startDate: uint32(block.timestamp),
            detailsHash: detailsHash
        });
    }

    function addFunds(uint256 agreementId) public payable
            onlyDepositor(agreementId) inStatus(Status.Funded, agreementId) {
        _escrow[agreementId].amount += uint96(msg.value);
        emit FundsAdded(agreementId, msg.sender, uint96(msg.value), _escrow[agreementId].amount);
    }

    function cancelAgreement(uint256 agreementId) public 
            onlyDepositor(agreementId) inStatus(Status.Funded, agreementId) {
        _escrow[agreementId].status = Status.Canceled;
        emit AgreementCanceled(agreementId);
    }

    function approveAgreement(uint256 agreementId) public 
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
        require(block.timestamp > _escrow[agreementId].deadlineDate, "You cannot raise dispute before the deadline");
        _escrow[agreementId].status = Status.Disputed;
        _disputes[agreementId] = Dispute({
            arbitrator: payable(0),
            feePercentage: uint32(DEFAULT_ARBITRATOR_PERCENTAGE),
            feeAmount: 0,
            agreed: false,
            startDate: uint32(block.timestamp),
            assignedDate: 0,
            refundAmount: 0,
            releasedAmount: 0
        });
        emit DisputeRaised(agreementId);
    }

    function registerArbitrator(uint256 agreementId, address payable arbitrator, uint32 feePercentage) public 
            onlyDepositorOrBeneficiary(agreementId) checkAddress(arbitrator) inStatus(Status.Disputed, agreementId) {
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
            if (_disputes[agreementId].arbitrator != arbitrator ||
                    _disputes[agreementId].feePercentage != feePercentage) {
                revert WrongArbitrator(_disputes[agreementId].arbitrator, arbitrator,
                    _disputes[agreementId].feePercentage, feePercentage);
            }
            // depositor set an arbitrator, beneficiary - agrees
            _disputes[agreementId].agreed = true;
            emit ArbitratorAgreed(agreementId, arbitrator, true);
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
        uint randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % _arbitratorsPool.length;
        _disputes[agreementId].arbitrator = payable(_arbitratorsPool[randomIndex]);
        _disputes[agreementId].agreed = true;
        _disputes[agreementId].assignedDate = uint32(block.timestamp);
        _assignedAgreements[_arbitratorsPool[randomIndex]].push(agreementId);
        emit PoolArbitratorAssigned(agreementId, _arbitratorsPool[randomIndex]);
    }

    function resolveDispute(uint256 agreementId) public
            onlyDepositorOrBeneficiary(agreementId) inStatus(Status.Disputed, agreementId) {
        // if pool arbitrator doesn't resolve the dispute - set Unresolved status and split the escrow
        require(_disputes[agreementId].assignedDate != 0 && block.timestamp >= _disputes[agreementId].assignedDate + RESOLVE_DISPUTE_MAX_PERIOD, 
            "You can resolve dispute yourself in 2 days after the pool arbitrator assignment date");
        _disputes[agreementId].refundAmount = uint96(_escrow[agreementId].amount * UNRESOLVED_DISPUTE_REFUND_PERCENTAGE / 1_000_000);
        _disputes[agreementId].releasedAmount = _escrow[agreementId].amount - _disputes[agreementId].refundAmount;
        _escrow[agreementId].status = Status.Unresolved;
        // check and remove agreement from assigned to the pool arbitrator
        if (_assignedAgreements[_disputes[agreementId].arbitrator].length > 0) {
            removeAgreementFromAssigned(_disputes[agreementId].arbitrator, agreementId);
        }
        emit DisputeUnresolved(agreementId, uint32(UNRESOLVED_DISPUTE_REFUND_PERCENTAGE), _disputes[agreementId].refundAmount);
    }

    function resolveDispute(uint256 agreementId, uint32 refundPercentage) public
            onlyArbitrator(agreementId) inStatus(Status.Disputed, agreementId) {
        require(refundPercentage >= 0 && refundPercentage <= 1000000, "Refunded percent should be between 0 and 1000000");
        _disputes[agreementId].feeAmount = _escrow[agreementId].amount *  _disputes[agreementId].feePercentage / 1_000_000;
        _disputes[agreementId].refundAmount = (_escrow[agreementId].amount - _disputes[agreementId].feeAmount) * refundPercentage / 1_000_000;
        _disputes[agreementId].releasedAmount = _escrow[agreementId].amount - _disputes[agreementId].feeAmount - _disputes[agreementId].refundAmount;
        _escrow[agreementId].status = Status.Resolved;
        // check and remove agreement from assigned to the pool arbitrator
        if (_assignedAgreements[_disputes[agreementId].arbitrator].length > 0) {
            removeAgreementFromAssigned(_disputes[agreementId].arbitrator, agreementId);
        }
        emit DisputeResolved(agreementId, refundPercentage, _disputes[agreementId].feeAmount, 
            _disputes[agreementId].refundAmount, _disputes[agreementId].releasedAmount);
    }

    function addPoolArbitrator(address arbitrator) public onlyOwner checkAddress(arbitrator) {
        require(_assignedAgreements[arbitrator].length == 0, "Arbitrator already in the pool");
        for (uint256 i = 0; i < _arbitratorsPool.length; i++) {
            if (_arbitratorsPool[i] == arbitrator) {
                revert ArbitratorInPool(arbitrator);
            }
        }
        _arbitratorsPool.push(arbitrator);
        emit PoolArbitratorAdded(arbitrator);
    }

    function removePoolArbitrator(address arbitrator) public onlyOwner checkAddress(arbitrator) {
        require(_assignedAgreements[arbitrator].length == 0, "Arbitrator has active agreements");
        for (uint256 i = 0; i < _arbitratorsPool.length; i++) {
            if (_arbitratorsPool[i] == arbitrator) {
                _arbitratorsPool[i] = _arbitratorsPool[_arbitratorsPool.length - 1];
                _arbitratorsPool.pop();
                delete _assignedAgreements[arbitrator];
                emit PoolArbitratorRemoved(arbitrator);
                return;
            }
        }
        revert ArbitratorNotInPool(arbitrator);
    }

    function removeAgreementFromAssigned(address arbitrator, uint256 agreementId) private {
        for (uint256 i = 0; i < _assignedAgreements[arbitrator].length; i++) {
            if (_assignedAgreements[arbitrator][i] == agreementId) {
                _assignedAgreements[arbitrator][i] = _assignedAgreements[arbitrator][_assignedAgreements[arbitrator].length - 1];
                _assignedAgreements[arbitrator].pop();
                break;
            }
        }
    }

    function withdrawFunds(uint256 agreementId) public payable nonReentrant {
        Agreement memory agreement = _escrow[agreementId];
        if (agreement.beneficiary == msg.sender) {
            if (agreement.status == Status.Closed) {
                require(_escrow[agreementId].amount > 0, "Funds are not available");
                uint96 amount = _escrow[agreementId].amount;
                _escrow[agreementId].amount = 0;
                agreement.beneficiary.transfer(amount);
                emit FundsWithdrawn(agreementId, msg.sender, amount);
                return;
            } else if (agreement.status == Status.Resolved) {
                require(_disputes[agreementId].releasedAmount > 0, "Funds are not available");
                uint96 releasedAmount = _disputes[agreementId].releasedAmount;
                _disputes[agreementId].releasedAmount = 0;
                agreement.beneficiary.transfer(releasedAmount);
                emit FundsWithdrawn(agreementId, msg.sender, releasedAmount);
                return;
            } else if (agreement.status == Status.Unresolved) {
                require(_disputes[agreementId].releasedAmount > 0, "Funds are not available");
                uint96 releasedAmount = _disputes[agreementId].releasedAmount;
                _disputes[agreementId].releasedAmount = 0;
                agreement.beneficiary.transfer(releasedAmount);
                emit FundsWithdrawn(agreementId, msg.sender, releasedAmount);
                return;
            }
        } else if (agreement.depositor == msg.sender) {
            if (agreement.status == Status.Canceled || agreement.status == Status.Rejected || 
                    agreement.status == Status.Refunded) {
                require(_escrow[agreementId].amount > 0, "Funds are not available");
                uint96 amount = _escrow[agreementId].amount;
                _escrow[agreementId].amount = 0;
                agreement.depositor.transfer(amount);
                emit FundsWithdrawn(agreementId, msg.sender, amount);
                return;
            } else if(agreement.status == Status.Resolved || agreement.status == Status.Unresolved) {
                require(_disputes[agreementId].refundAmount > 0, "Funds are not available");
                uint96 refundAmount = _disputes[agreementId].refundAmount;
                _disputes[agreementId].refundAmount = 0;
                agreement.depositor.transfer(refundAmount);
                emit FundsWithdrawn(agreementId, msg.sender, refundAmount);
                return;
            }
        } else if (_disputes[agreementId].arbitrator == msg.sender) {
            if (agreement.status == Status.Resolved) {
                require(_disputes[agreementId].feeAmount > 0, "Funds are not available");
                uint96 feeAmount = _disputes[agreementId].feeAmount;
                _disputes[agreementId].feeAmount = 0;
                _disputes[agreementId].arbitrator.transfer(feeAmount);
                emit FundsWithdrawn(agreementId, msg.sender, feeAmount);
                return;
            }
        }
        revert WithdrawProhibited(msg.sender, agreement.status);
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
        revert NoBalance(msg.sender, agreement.status);
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