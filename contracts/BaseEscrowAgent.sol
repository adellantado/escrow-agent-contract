// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IEscrowAgent.sol";

contract BaseEscrowAgent is IEscrowAgent, ReentrancyGuard {

    uint256 public constant RELEASE_FUNDS_AFTER_DEADLINE = 3 days;
    uint256 public constant AGREE_ON_ARBITRATOR_MAX_PERIOD = 2 days;
    uint256 public constant RESOLVE_DISPUTE_MAX_PERIOD = 2 days;
    uint32 public constant UNRESOLVED_DISPUTE_REFUND_PERCENTAGE = 500000;
    uint32 public constant DEFAULT_ARBITRATOR_PERCENTAGE = 10000;
    
    modifier checkAddress(address user) {
        require(user != address(0), "Address is zero");
        _;
    }
}