// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./abstracts/Ownable.sol";

contract parameterSetup is Ownable {
    uint256 public percentage;
    uint256 public fee;

    constructor() {
        percentage = 95;
        fee = 1;
    }

    function setPercentage(uint256 _percetage) public onlyOwner {
        percentage = _percetage;
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }
}
