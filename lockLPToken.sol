// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/IOurOwnLPERC20.sol";

interface IparameterSetup {
    function viewLockTime() external returns (uint256);
}

contract lockLPToken {
    struct Items {
        address tokenAddress;
        uint256 tokenAmount;
        uint256 unlockTime;
        bool withdrawn;
    }

    uint256 lockTime;
    IparameterSetup public parameterSetup;

    constructor(address _parameterSetup) {
        parameterSetup = IparameterSetup(_parameterSetup);
        lockTime = parameterSetup.viewLockTime();
    }

    function setLockTime() public {
        lockTime = parameterSetup.viewLockTime();
    }

    uint256 public depositId = 0;
    uint256[] public allDepositIds;

    mapping(uint256 => Items) public lockedToken;

    // Token -> { sender1 -> locked amount }
    mapping(address => mapping(address => uint256)) public walletTokenBalance;

    event TokensLocked(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount,
        uint256 unlockTime,
        uint256 depositId
    );
    event TokensWithdrawn(
        address indexed tokenAddress,
        address indexed receiver,
        uint256 amount
    );

    event TokensLockedAddTime(uint256 _id, uint256 _unlockTime);

    // Providers Must Lock all LP Tokens for 1 year
    function lockTokens(
        address _tokenAddress,
        uint256 _amount
    ) external returns (uint256 _id) {
        require(_amount > 0, "LP Token Amount Must Be 0");
        require(
            IOurOwnLPERC20(_tokenAddress).approve(address(this), _amount),
            "Failed to approve tokens"
        );
        require(
            IOurOwnLPERC20(_tokenAddress).transferFrom(
                msg.sender,
                address(this),
                _amount
            ),
            "Failed to transfer tokens to locker"
        );

        uint256 lockAmount = _amount;

        walletTokenBalance[_tokenAddress][msg.sender] += _amount;
        uint256 _unlockTime = block.timestamp + lockTime;
        _id = ++depositId;
        lockedToken[_id].tokenAddress = _tokenAddress;
        lockedToken[_id].tokenAmount = lockAmount;
        lockedToken[_id].unlockTime = _unlockTime;
        lockedToken[_id].withdrawn = false;

        allDepositIds.push(_id);

        emit TokensLocked(
            _tokenAddress,
            msg.sender,
            _amount,
            _unlockTime,
            depositId
        );
    }

    function getTotalTokenBalance(
        address _tokenAddress
    ) public view returns (uint256) {
        return IOurOwnLPERC20(_tokenAddress).balanceOf(address(this));
    }

    function getTokenBalanceByAddress(
        address _tokenAddress,
        address _walletAddress
    ) public view returns (uint256) {
        return walletTokenBalance[_tokenAddress][_walletAddress];
    }

    function getAllDepositIds() public view returns (uint256[] memory) {
        return allDepositIds;
    }

    function getDepositDetails(
        uint256 _id
    ) public view returns (address, uint256, uint256, bool) {
        return (
            lockedToken[_id].tokenAddress,
            lockedToken[_id].tokenAmount,
            lockedToken[_id].unlockTime,
            lockedToken[_id].withdrawn
        );
    }
}
