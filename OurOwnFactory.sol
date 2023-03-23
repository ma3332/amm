// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./interfaces/IUniswapV2Factory.sol";
import "./OurOwnPair.sol";

contract OurOwnFactory is IUniswapV2Factory {
    address public override feeTo;
    address public override feeToSetter;
    address public override migrator;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(OurOwnPair).creationCode);
    }

    function getByteCode() external pure returns (bytes memory) {
        return type(OurOwnPair).creationCode;
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external override returns (address pair) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS"); // single check is sufficient
        bytes memory bytecode = type(OurOwnPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        /*
        create2(v, p, n, s)
        create new contract with code at memory p to p + n
        and send v wei
        and return the new address
        where new address = first 20 bytes of keccak256(0xff + address(this) + s + keccak256(mem[p…(p+n)))
              s = big-endian 256-bit value
        */
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        OurOwnPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeTo = _feeTo;
    }

    function setMigrator(address _migrator) external override {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        migrator = _migrator;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
