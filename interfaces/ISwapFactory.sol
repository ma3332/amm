// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface ISwapFactory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeToSetter() external view returns (address);

    function migrator() external view returns (address);

    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function setFeeToSetter(address) external;

    function setMigrator(address) external;
}
