// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleSwap {
    struct Pool {
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalLiquidity;
        mapping(address => uint256) liquidityBalance;
    }

    mapping(bytes32 => Pool) public pools;

    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }

    function addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline   
    )external returns (uint amountA, uint amountB, uint liquidity) {
    require(block.timestamp <= deadline, "Deadline passed");
    require(amountAMin > 0 && amountBMin > 0, "Minimum amounts must be > 0");
    require(amountADesired >= amountAMin && amountBDesired >= amountBMin, "Slippage too high");

        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

        if (pool.totalLiquidity == 0) {
            liquidity = sqrt(amountADesired * amountBDesired);
        } else {
            liquidity = min(
                (amountADesired * pool.totalLiquidity) / pool.reserveA,
                (amountBDesired * pool.totalLiquidity) / pool.reserveB
            );
        }

        pool.reserveA += amountADesired;
        pool.reserveB += amountBDesired;
        pool.totalLiquidity += liquidity;
        pool.liquidityBalance[to] += liquidity;

        return (amountADesired, amountBDesired, liquidity);
    }

    function removeLiquidity(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
    ) external returns (uint amountA, uint amountB) {
    require(block.timestamp <= deadline, "Deadline passed");
    require(amountAMin > 0 && amountBMin > 0, "Minimum amounts must be > 0");

        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        require(pool.liquidityBalance[msg.sender] >= liquidity, "Not enough liquidity");

        amountA = (liquidity * pool.reserveA) / pool.totalLiquidity;
        amountB = (liquidity * pool.reserveB) / pool.totalLiquidity;

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage too high");

        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        pool.totalLiquidity -= liquidity;
        pool.liquidityBalance[msg.sender] -= liquidity;

        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);

        return (amountA, amountB);
    }

    event SwapExecuted(address indexed user, address tokenIn, address tokenOut, uint amountIn, uint amountOut);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(block.timestamp <= deadline, "Transaction expired");
        require(path.length == 2, "Only 1 hop allowed");
        require(amountIn > 0, "Zero input amount");

        bytes32 poolId = getPoolId(path[0], path[1]);
        Pool storage pool = pools[poolId];

        uint reserveIn = pool.reserveA;
        uint reserveOut = pool.reserveB;

        uint amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
        require(amountOut >= amountOutMin, "Slippage too high");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[1]).transfer(to, amountOut);

        pool.reserveA += amountIn;
        pool.reserveB -= amountOut;

        emit SwapExecuted(msg.sender, path[0], path[1], amountIn, amountOut);

        amounts = new uint[](2) ;
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }

    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        require(pool.reserveA > 0 && pool.reserveB > 0, "Empty pool");

        price = (pool.reserveB * 1e18) / pool.reserveA;
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, "Invalid input");
        require(reserveIn > 0 && reserveOut > 0, "Invalid reserves");

        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y == 0) return 0;
        if (y <= 3) return 1;

        z = y;
        uint x = (y / 2) + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }
}
