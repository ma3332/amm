// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./abstracts/Ownable.sol";

contract parameterSetup is Ownable {
    uint256 public percentage;
    uint256 public fee;
    uint256 public lockTime;

    constructor() {
        percentage = 95; // 95% need to be deposited at 1st time
        fee = 1; // 0.1% fee for LP providers
        lockTime = 31536000; // 1 year lock LP is required
    }

    function setPercentage(uint256 _percetage) public onlyOwner {
        percentage = _percetage;
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    function setLockTime(uint256 _lockTime) public onlyOwner {
        lockTime = _lockTime;
    }

    function viewPercentage() public view returns (uint256 percent) {
        percent = percentage;
    }

    function viewFee() public view returns (uint256 _viewFee) {
        _viewFee = fee;
    }

    function viewLockTime() public view returns (uint256 viewLock) {
        viewLock = lockTime;
    }
}
