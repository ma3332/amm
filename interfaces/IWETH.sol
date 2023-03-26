// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);
}
