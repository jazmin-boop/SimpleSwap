
```solidity

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleSwap {
    /**
     * @dev Structure to represent a liquidity pool between two tokens.
     * @param reserveA The amount of token A held in the pool.
     * @param reserveB The amount of token B held in the pool.
     * @param totalLiquidity The total amount of liquidity tokens minted for this pool.
     * @param liquidityBalance A mapping from user address to their liquidity token balance.
     */
    struct Pool {
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalLiquidity;
        mapping(address => uint256) liquidityBalance;
    }

    /// @dev Mapping from a unique pool ID (bytes32) to its Pool struct.
    mapping(bytes32 => Pool) public pools;

    /**
     * @dev Generates a unique ID for a given token pair.
     * @param tokenA Address of the first token in the pair.
     * @param tokenB Address of the second token in the pair.
     * @return bytes32 A unique identifier for the token pair pool.
     */
    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }

    /**
     * @dev Adds liquidity to a token pair pool.
     * Users provide equal value of two tokens to the pool to become liquidity providers.
     * The amount of liquidity tokens received is proportional to the liquidity provided.
     * @param tokenA Address of the first token.
     * @param tokenB Address of the second token.
     * @param amountADesired The desired amount of token A to add.
     * @param amountBDesired The desired amount of token B to add.
     * @param amountAMin The minimum amount of token A to accept.
     * @param amountBMin The minimum amount of token B to accept.
     * @param to The address where the liquidity tokens will be minted.
     * @param deadline The timestamp by which the transaction must be included.
     * @return amountA The actual amount of token A added to the pool.
     * @return amountB The actual amount of token B added to the pool.
     * @return liquidity The amount of liquidity tokens minted and sent to 'to'.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        require(block.timestamp <= deadline, "Deadline passed");
        require(amountAMin > 0 && amountBMin > 0, "Minimum amounts must be > 0");
        require(amountADesired >= amountAMin && amountBDesired >= amountBMin, "Slippage too high");

        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];

        // Transfer tokens from the caller to the contract
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

        if (pool.totalLiquidity == 0) {
            // If it's the first liquidity addition, liquidity tokens are sqrt(amountA * amountB)
            liquidity = sqrt(amountADesired * amountBDesired);
        } else {
            // For subsequent additions, liquidity is proportional to the existing reserves
            liquidity = min(
                (amountADesired * pool.totalLiquidity) / pool.reserveA,
                (amountBDesired * pool.totalLiquidity) / pool.reserveB
            );
        }

        // Update pool reserves and total liquidity
        pool.reserveA += amountADesired;
        pool.reserveB += amountBDesired;
        pool.totalLiquidity += liquidity;
        pool.liquidityBalance[to] += liquidity;

        return (amountADesired, amountBDesired, liquidity);
    }

    /**
     * @dev Removes liquidity from a token pair pool.
     * Users burn their liquidity tokens to receive a proportional share of the pool's reserves.
     * @param tokenA Address of the first token.
     * @param tokenB Address of the second token.
     * @param liquidity The amount of liquidity tokens to burn.
     * @param amountAMin The minimum amount of token A to receive.
     * @param amountBMin The minimum amount of token B to receive.
     * @param to The address where the withdrawn tokens will be sent.
     * @param deadline The timestamp by which the transaction must be included.
     * @return amountA The actual amount of token A withdrawn from the pool.
     * @return amountB The actual amount of token B withdrawn from the pool.
     */
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

        // Calculate the amounts of tokens to withdraw based on liquidity burned
        amountA = (liquidity * pool.reserveA) / pool.totalLiquidity;
        amountB = (liquidity * pool.reserveB) / pool.totalLiquidity;

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage too high");

        // Update pool reserves and total liquidity
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        pool.totalLiquidity -= liquidity;
        pool.liquidityBalance[msg.sender] -= liquidity;

        // Transfer withdrawn tokens to the recipient
        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);

        return (amountA, amountB);
    }

    /// @dev Emitted when a token swap is successfully executed.
    /// @param user The address of the user who initiated the swap.
    /// @param tokenIn The address of the token that was input.
    /// @param tokenOut The address of the token that was output.
    /// @param amountIn The amount of tokenIn that was swapped.
    /// @param amountOut The amount of tokenOut that was received.
    event SwapExecuted(address indexed user, address tokenIn, address tokenOut, uint amountIn, uint amountOut);

    /**
     * @dev Swaps an exact amount of `tokenIn` for `tokenOut`.
     * This function supports single-hop swaps between two tokens within a pool.
     * The `path` array should contain exactly two token addresses: [tokenIn, tokenOut].
     * @param amountIn The exact amount of the input token to swap.
     * @param amountOutMin The minimum amount of the output token to receive (slippage control).
     * @param path An array of token addresses representing the swap path
     * @param to The address to which the output tokens will be sent.
     * @param deadline The timestamp by which the transaction must be included.
     * @return amounts An array containing the input amount and the output amount.
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(block.timestamp <= deadline, "Transaction expired");
        require(path.length == 2, "Only 1 hop allowed"); // Enforces single-hop swaps
        require(amountIn > 0, "Zero input amount");

        bytes32 poolId = getPoolId(path[0], path[1]);
        Pool storage pool = pools[poolId];

        // Determine which reserve is for the input token and which for the output token
        // This assumes that the pool's reserves are always aligned with the token addresses
        // used to generate the poolId. A more robust implementation might check `tokenA` and `tokenB`
        // against `path[0]` and `path[1]` and swap `reserveA`/`reserveB` accordingly.
        uint reserveIn = pool.reserveA;
        uint reserveOut = pool.reserveB;

        // Calculate the amount of output tokens received based on the constant product formula (x*y=k)
        // This formula is simplified and doesn't include fees.
        uint amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
        require(amountOut >= amountOutMin, "Slippage too high");

        // Transfer input token from caller to the contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        // Transfer output token from the contract to the recipient
        IERC20(path[1]).transfer(to, amountOut);

        // Update pool reserves
        pool.reserveA += amountIn;
        pool.reserveB -= amountOut;

        emit SwapExecuted(msg.sender, path[0], path[1], amountIn, amountOut);

        amounts = new uint[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }

    /**
     * @dev Calculates the spot price of tokenB in terms of tokenA 
     * The price is scaled by 1e18 to provide a higher precision fixed-point number.
     * @param tokenA Address of the first token.
     * @param tokenB Address of the second token.
     * @return price The price of tokenB per unit of tokenA, scaled by 1e18.
     */
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        require(pool.reserveA > 0 && pool.reserveB > 0, "Empty pool");

        // Price is (reserveB / reserveA) * 1e18
        price = (pool.reserveB * 1e18) / pool.reserveA;
    }

    /**
     * @dev Calculates the amount of output tokens received for a given input amount and reserves.
     * This is a pure function that does not modify the state of the contract.
     * It uses the constant product formula (x*y=k) to determine the output amount.
     * @param amountIn The amount of input tokens.
     * @param reserveIn The reserve of the input token in the pool.
     * @param reserveOut The reserve of the output token in the pool.
     * @return amountOut The calculated amount of output tokens.
     */
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, "Invalid input");
        require(reserveIn > 0 && reserveOut > 0, "Invalid reserves");

        // Constant product formula: (reserveIn + amountIn) * (reserveOut - amountOut) = reserveIn * reserveOut
        // Rearranging for amountOut: amountOut = (amountIn * reserveOut) / (reserveIn + amountIn)
        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    /**
     * @dev Returns the minimum of two unsigned integers.
     * @param a The first unsigned integer.
     * @param b The second unsigned integer.
     * @return The smaller of the two input values.
     */
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    /**
     * @dev Calculates the integer square root of a non-negative integer.
     * This is a common utility function for calculating liquidity tokens in AMMs.
     * @param y The number for which to calculate the square root.
     * @return z The integer square root of y.
     */
    function sqrt(uint y) internal pure returns (uint z) {
        if (y == 0) return 0;
        if (y <= 3) return 1;

        z = y;
        uint x = (y / 2) + 1; // Initial guess
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }
}

```


## Example of Use
1.The user calls addLiquidity() and sends equal values of tokenA and tokenB.
2.Another user does a swap using swapExactTokensForTokens().
3.A provider can call removeLiquidity() to get their tokens back.

###Technical Notes

1.Swap Formula: The swap uses the classic AMM formula:
x * y = k (no fees included).

2.Deadline: Uses Unix timestamps. On the frontend or console, you can set it like this:
Math.floor(Date.now() / 1000) + 600
(This gives 10 minutes to do the transaction.)

3.First Liquidity: When the pool starts, the amount of liquidity tokens given is:
sqrt(amountADesired * amountBDesired)

4.Token Order: The order of tokenA and tokenB matters.
Always use the same order to avoid duplicate pools or errors.


