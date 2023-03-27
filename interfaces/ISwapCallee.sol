// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface ISwapCallee {
    function swapCall(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external;
}
