// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./libraries/TransferHelper.sol";
import "./interfaces/ISwapRouter01.sol";
import "./interfaces/ISwapFactory.sol";
import "./interfaces/IOurOwnLPERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ISwapPair.sol";

interface IlockLPToken {
    struct Items {
        address tokenAddress;
        uint256 tokenAmount;
        uint256 unlockTime;
        bool withdrawn;
    }

    function lockTokens(address, uint256) external returns (uint256);

    function lockedToken(uint256 _id) external view returns (Items memory);
}

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);

    function totalSupply() external view returns (uint256);
}

interface IparameterSetup {
    function viewPercentage() external returns (uint256);

    function viewFee() external returns (uint256);
}

contract OurOwnRouterV1 is ISwapRouter01 {
    address public immutable override factory;
    address public immutable override WETH;
    uint256 public percentage;
    uint256 public fee;

    IlockLPToken public lockLPToken;
    IparameterSetup public parameterSetup;

    event ETHPairCreate(address pair, uint256 id, uint256 liquidityLPETH);
    event pairCreated(address pair, uint256 id, uint256 liquidityLP);
    mapping(address => uint256) public initalID;
    mapping(address => uint256) public initalTotalSupply;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    constructor(
        address _factory,
        address _WETH,
        address _lockLPToken,
        address _parameterSetup
    ) {
        factory = _factory;
        WETH = _WETH;
        lockLPToken = IlockLPToken(_lockLPToken);
        parameterSetup = IparameterSetup(_parameterSetup);
        percentage = parameterSetup.viewPercentage();
        fee = parameterSetup.viewFee();
    }

    function setFee() public {
        fee = parameterSetup.viewFee();
    }

    function setPercentage() public {
        percentage = parameterSetup.viewPercentage();
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    )
        internal
        virtual
        returns (uint256 amountA, uint256 amountB, bool newLP, address origin)
    {
        // create the pair if it doesn't exist yet
        if (ISwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            ISwapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = getReserves(
            factory,
            tokenA,
            tokenB
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
            require(
                amountADesired >=
                    (IERC20(tokenA).totalSupply() * percentage) / 100 ||
                    amountBDesired >=
                    (IERC20(tokenB).totalSupply() * percentage) / 100,
                "Not allow to deposit"
            );
            if (
                amountADesired >=
                (IERC20(tokenA).totalSupply() * percentage) / 100
            ) {
                origin = tokenA;
            } else {
                origin = tokenB;
            }
            newLP = true;
        } else {
            uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    "SwapRouter: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                require(
                    amountAOptimal >= amountAMin,
                    "SwapRouter: INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
            newLP = false;
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        bool newLP;
        address origin;
        (amountA, amountB, newLP, origin) = _addLiquidity(
            _fromToken(msg.data),
            _destToken(msg.data),
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        address pair = pairFor(
            factory,
            _fromToken(msg.data),
            _destToken(msg.data)
        );
        TransferHelper.safeTransferFrom(
            _fromToken(msg.data),
            msg.sender,
            pair,
            amountA
        );
        TransferHelper.safeTransferFrom(
            _destToken(msg.data),
            msg.sender,
            pair,
            amountB
        );
        liquidity = ISwapPair(pair).mint(to);
        uint256 id = lockLPToken.lockTokens(pair, liquidity);
        if (newLP) {
            initalID[pair] = id;
            initalTotalSupply[origin] = IERC20(origin).totalSupply();
        }
        emit pairCreated(pair, id, liquidity);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        bool newLP;
        address origin;
        (amountToken, amountETH, newLP, origin) = _addLiquidity(
            _fromToken(msg.data),
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = pairFor(factory, _fromToken(msg.data), WETH);
        TransferHelper.safeTransferFrom(
            _fromToken(msg.data),
            msg.sender,
            pair,
            amountToken
        );
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = ISwapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH)
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        uint256 id = lockLPToken.lockTokens(pair, liquidity);
        if (newLP) {
            initalID[pair] = id;
            initalTotalSupply[origin] = IERC20(origin).totalSupply();
        }
        emit ETHPairCreate(pair, id, liquidity);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 _id,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        require(msg.sender == tx.origin, "Not allowed");
        address pair = pairFor(
            factory,
            _fromToken(msg.data),
            _destToken(msg.data)
        );
        require(
            lockLPToken.lockedToken(_id).unlockTime > block.timestamp,
            "Not yet withdraw"
        );
        require(
            lockLPToken.lockedToken(_id).tokenAddress == pair,
            "Not correct pair"
        );
        ISwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = ISwapPair(pair).burn(to);
        (address token0, ) = sortTokens(
            _fromToken(msg.data),
            _destToken(msg.data)
        );
        (amountA, amountB) = _fromToken(msg.data) == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(amountA >= amountAMin, "SwapRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "SwapRouter: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityETH(
        address token,
        uint256 _id,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH)
    {
        require(msg.sender == tx.origin, "Not allowed");
        address pair = pairFor(factory, _fromToken(msg.data), WETH);
        require(
            lockLPToken.lockedToken(_id).unlockTime > block.timestamp,
            "Not yet withdraw"
        );
        require(
            lockLPToken.lockedToken(_id).tokenAddress == pair,
            "Not correct pair"
        );
        ISwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = ISwapPair(pair).burn(to);
        (address token0, ) = sortTokens(_fromToken(msg.data), WETH);
        (amountToken, amountETH) = _fromToken(msg.data) == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountToken >= amountTokenMin,
            "SwapRouter: INSUFFICIENT_A_AMOUNT"
        );
        require(amountETH >= amountETHMin, "SwapRouter: INSUFFICIENT_B_AMOUNT");
        TransferHelper.safeTransfer(_fromToken(msg.data), to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 _id,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        require(msg.sender == tx.origin, "Not allowed");
        address pair = pairFor(factory, tokenA, tokenB);
        require(
            lockLPToken.lockedToken(_id).unlockTime > block.timestamp,
            "Not yet withdraw"
        );
        require(
            lockLPToken.lockedToken(_id).tokenAddress == pair,
            "Not correct pair"
        );
        {
            uint256 value = approveMax ? type(uint256).max : liquidity;
            ISwapPair(pair).permit(
                msg.sender,
                address(this),
                value,
                deadline,
                v,
                r,
                s
            );
        }
        {
            ISwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        }
        {
            (uint256 amount0, uint256 amount1) = ISwapPair(pair).burn(to);
            (address token0, ) = sortTokens(
                _fromToken(msg.data),
                _destToken(msg.data)
            );

            {
                (amountA, amountB) = _fromToken(msg.data) == token0
                    ? (amount0, amount1)
                    : (amount1, amount0);
            }

            require(amountA >= amountAMin, "SwapRouter: INSUFFICIENT_A_AMOUNT");
            require(amountB >= amountBMin, "SwapRouter: INSUFFICIENT_B_AMOUNT");
        }
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 _id,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        virtual
        override
        returns (uint256 amountToken, uint256 amountETH)
    {
        require(msg.sender == tx.origin, "Not allowed");
        address pair = pairFor(factory, token, WETH);
        require(
            lockLPToken.lockedToken(_id).unlockTime > block.timestamp,
            "Not yet withdraw"
        );
        require(
            lockLPToken.lockedToken(_id).tokenAddress == pair,
            "Not correct pair"
        );
        {
            uint256 value = approveMax ? type(uint256).max : liquidity;
            ISwapPair(pair).permit(
                msg.sender,
                address(this),
                value,
                deadline,
                v,
                r,
                s
            );
        }
        ISwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        {
            (uint256 amount0, uint256 amount1) = ISwapPair(pair).burn(to);
            (address token0, ) = sortTokens(_fromToken(msg.data), WETH);
            (amountToken, amountETH) = _fromToken(msg.data) == token0
                ? (amount0, amount1)
                : (amount1, amount0);
        }
        require(
            amountToken >= amountTokenMin,
            "SwapRouter: INSUFFICIENT_A_AMOUNT"
        );
        require(amountETH >= amountETHMin, "SwapRouter: INSUFFICIENT_B_AMOUNT");
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? pairFor(factory, output, path[i + 2])
                : _to;
            ISwapPair(pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (initalTotalSupply[path[0]] != 0) {
            require(
                initalTotalSupply[path[0]] == IERC20(path[0]).totalSupply(),
                "Token is mintable"
            );
        }
        amounts = getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            pairFor(factory, path[0], path[1]),
            amounts[0]
        );

        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (initalTotalSupply[path[0]] != 0) {
            require(
                initalTotalSupply[path[0]] == IERC20(path[0]).totalSupply(),
                "Token is mintable"
            );
        }
        amounts = getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= amountInMax,
            "SwapRouter: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, "SwapRouter: INVALID_PATH");
        amounts = getAmountsOut(factory, msg.value, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(pairFor(factory, path[0], path[1]), amounts[0])
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[path.length - 1] == WETH, "SwapRouter: INVALID_PATH");
        if (initalTotalSupply[path[0]] != 0) {
            require(
                initalTotalSupply[path[0]] == IERC20(path[0]).totalSupply(),
                "Token is mintable"
            );
        }
        amounts = getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= amountInMax,
            "SwapRouter: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[path.length - 1] == WETH, "SwapRouter: INVALID_PATH");
        if (initalTotalSupply[path[0]] != 0) {
            require(
                initalTotalSupply[path[0]] == IERC20(path[0]).totalSupply(),
                "Token is mintable"
            );
        }
        amounts = getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, "SwapRouter: INVALID_PATH");
        amounts = getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "SwapRouter: EXCESSIVE_INPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(pairFor(factory, path[0], path[1]), amounts[0])
        );
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0])
            TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** LIBRARY FUNCTIONS ****
    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(
        address factoryPram,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factoryPram,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"97ce6f1772b40f5d2163d98e289ffe4ce4eb434b0abb05857bd8721564d03ae6" // init code hash, need to change here
                        )
                    )
                )
            )
        );
    }

    // fetches and sorts the reserves for a pair
    function getReserves(
        address factoryPram,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = ISwapPair(
            pairFor(factoryPram, tokenA, tokenB)
        ).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal view virtual override returns (uint256 amountB) {
        require(amountA > 0, "INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // Swap fee is fixed = 0.1% = 1/1000. Liquidity providers will receive this fee
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view virtual override returns (uint256 amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * (1000 - fee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view virtual override returns (uint256 amountIn) {
        require(amountOut > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * (1000 - fee);
        amountIn = (numerator / denominator) + 1;
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(
        address factoryPram,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                factoryPram,
                path[i],
                path[i + 1]
            );
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(
        address factoryPram,
        uint256 amountOut,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                factoryPram,
                path[i - 1],
                path[i]
            );
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    // Helps to avoid "Stack too deep" in swap() method
    function _fromToken(
        bytes memory mgsData
    ) internal pure returns (address token) {
        assembly {
            token := mload(add(mgsData, 36))
        }
        return token;
    }

    // Helps to avoid "Stack too deep" in swap() method
    function _destToken(
        bytes memory mgsData
    ) internal pure returns (address token) {
        assembly {
            token := mload(add(mgsData, 68))
        }
        return token;
    }
}
