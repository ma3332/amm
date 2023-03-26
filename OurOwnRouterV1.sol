// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./libraries/UniswapV2Library.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IOurOwnLPERC20.sol";
import "./interfaces/IWETH.sol";

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

contract OurOwnRouterV1 is IUniswapV2Router01 {
    address public immutable override factory;
    address public immutable override WETH;

    IlockLPToken public lockLPToken;

    event ETHPairCreate(address pair, uint256 id, uint256 liquidityLPETH);
    event pairCreated(address pair, uint256 id, uint256 liquidityLP);
    mapping(address => uint256) public initalID;
    mapping(address => uint256) public initalTotalSupply;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH, address _lockLPToken) {
        factory = _factory;
        WETH = _WETH;
        lockLPToken = IlockLPToken(_lockLPToken);
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
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            factory,
            tokenA,
            tokenB
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
            require(
                amountADesired >= (IERC20(tokenA).totalSupply() * 95) / 100 ||
                    amountBDesired >= (IERC20(tokenB).totalSupply() * 95) / 100,
                "Not allow to deposit"
            );
            if (amountADesired >= (IERC20(tokenA).totalSupply() * 95) / 100) {
                origin = tokenA;
            } else {
                origin = tokenB;
            }
            newLP = true;
        } else {
            uint256 amountBOptimal = UniswapV2Library.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    "UniswapV2Router: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = UniswapV2Library.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                require(
                    amountAOptimal >= amountAMin,
                    "UniswapV2Router: INSUFFICIENT_A_AMOUNT"
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
        address pair = UniswapV2Library.pairFor(
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
        liquidity = IUniswapV2Pair(pair).mint(to);
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
        address pair = UniswapV2Library.pairFor(
            factory,
            _fromToken(msg.data),
            WETH
        );
        TransferHelper.safeTransferFrom(
            _fromToken(msg.data),
            msg.sender,
            pair,
            amountToken
        );
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IUniswapV2Pair(pair).mint(to);
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
        address pair = UniswapV2Library.pairFor(
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
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0, ) = UniswapV2Library.sortTokens(
            _fromToken(msg.data),
            _destToken(msg.data)
        );
        (amountA, amountB) = _fromToken(msg.data) == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountA >= amountAMin,
            "UniswapV2Router: INSUFFICIENT_A_AMOUNT"
        );
        require(
            amountB >= amountBMin,
            "UniswapV2Router: INSUFFICIENT_B_AMOUNT"
        );
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
        address pair = UniswapV2Library.pairFor(
            factory,
            _fromToken(msg.data),
            WETH
        );
        require(
            lockLPToken.lockedToken(_id).unlockTime > block.timestamp,
            "Not yet withdraw"
        );
        require(
            lockLPToken.lockedToken(_id).tokenAddress == pair,
            "Not correct pair"
        );
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0, ) = UniswapV2Library.sortTokens(
            _fromToken(msg.data),
            WETH
        );
        (amountToken, amountETH) = _fromToken(msg.data) == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountToken >= amountTokenMin,
            "UniswapV2Router: INSUFFICIENT_A_AMOUNT"
        );
        require(
            amountETH >= amountETHMin,
            "UniswapV2Router: INSUFFICIENT_B_AMOUNT"
        );
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
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
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
            IUniswapV2Pair(pair).permit(
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
            IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        }
        {
            (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
            (address token0, ) = UniswapV2Library.sortTokens(
                _fromToken(msg.data),
                _destToken(msg.data)
            );

            {
                (amountA, amountB) = _fromToken(msg.data) == token0
                    ? (amount0, amount1)
                    : (amount1, amount0);
            }

            require(
                amountA >= amountAMin,
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT"
            );
            require(
                amountB >= amountBMin,
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT"
            );
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
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
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
            IUniswapV2Pair(pair).permit(
                msg.sender,
                address(this),
                value,
                deadline,
                v,
                r,
                s
            );
        }
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        {
            (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
            (address token0, ) = UniswapV2Library.sortTokens(
                _fromToken(msg.data),
                WETH
            );
            (amountToken, amountETH) = _fromToken(msg.data) == token0
                ? (amount0, amount1)
                : (amount1, amount0);
        }
        require(
            amountToken >= amountTokenMin,
            "UniswapV2Router: INSUFFICIENT_A_AMOUNT"
        );
        require(
            amountETH >= amountETHMin,
            "UniswapV2Router: INSUFFICIENT_B_AMOUNT"
        );
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
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? UniswapV2Library.pairFor(factory, output, path[i + 2])
                : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output))
                .swap(amount0Out, amount1Out, to, new bytes(0));
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
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
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
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= amountInMax,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
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
        require(path[0] == WETH, "UniswapV2Router: INVALID_PATH");
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(
                UniswapV2Library.pairFor(factory, path[0], path[1]),
                amounts[0]
            )
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
        require(path[path.length - 1] == WETH, "UniswapV2Router: INVALID_PATH");
        if (initalTotalSupply[path[0]] != 0) {
            require(
                initalTotalSupply[path[0]] == IERC20(path[0]).totalSupply(),
                "Token is mintable"
            );
        }
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= amountInMax,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
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
        require(path[path.length - 1] == WETH, "UniswapV2Router: INVALID_PATH");
        if (initalTotalSupply[path[0]] != 0) {
            require(
                initalTotalSupply[path[0]] == IERC20(path[0]).totalSupply(),
                "Token is mintable"
            );
        }
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
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
        require(path[0] == WETH, "UniswapV2Router: INVALID_PATH");
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= msg.value,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(
                UniswapV2Library.pairFor(factory, path[0], path[1]),
                amounts[0]
            )
        );
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0])
            TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public view virtual override returns (uint256 amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public view virtual override returns (uint256 amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public view virtual override returns (uint256 amountIn) {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
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
